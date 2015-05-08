module Facet {
  export const POSSIBLE_TYPES: Lookup<number> = {
    'NULL': 1,
    'BOOLEAN': 1,
    'NUMBER': 1,
    'TIME': 1,
    'STRING': 1,
    'NUMBER_RANGE': 1,
    'TIME_RANGE': 1,
    'SET': 1,
    'SET/NULL': 1,
    'SET/BOOLEAN': 1,
    'SET/NUMBER': 1,
    'SET/TIME': 1,
    'SET/STRING': 1,
    'SET/NUMBER_RANGE': 1,
    'SET/TIME_RANGE': 1,
    'DATASET': 1
  };

  const GENERATIONS_REGEXP = /^\^+/;
  const TYPE_REGEXP = /:([A-Z\/_]+)$/;

  export class RefExpression extends Expression {
    static SIMPLE_NAME_REGEXP = /^([a-z_]\w*)$/i;

    static fromJS(parameters: ExpressionJS): RefExpression {
      var value: ExpressionValue;
      if (hasOwnProperty(parameters, 'nest')) {
        value = <any>parameters;
      } else {
        value = {
          op: 'ref',
          nest: 0,
          name: parameters.name,
          type: parameters.type
        }
      }
      return new RefExpression(value);
    }

    static parse(str: string): RefExpression {
      var refValue: ExpressionValue = { op: 'ref' };
      var match: RegExpMatchArray;

      match = str.match(GENERATIONS_REGEXP);
      if (match) {
        var nest = match[0].length;
        refValue.nest = nest;
        str = str.substr(nest);
      } else {
        refValue.nest = 0;
      }

      match = str.match(TYPE_REGEXP);
      if (match) {
        refValue.type = match[1];
        str = str.substr(0, str.length - match[0].length);
      }

      if (str[0] === '{' && str[str.length - 1] === '}') {
        str = str.substr(1, str.length - 2);
      }

      refValue.name = str;
      return new RefExpression(refValue);
    }

    static toSimpleName(variableName: string): string {
      if (!RefExpression.SIMPLE_NAME_REGEXP.test(variableName)) throw new Error('fail'); // ToDo: fix this
      return variableName
    }

    public nest: int;
    public name: string;
    public remote: string[];

    constructor(parameters: ExpressionValue) {
      super(parameters, dummyObject);
      this._ensureOp("ref");

      var name = parameters.name;
      if (typeof name !== 'string' || name.length === 0) {
        throw new TypeError("must have a nonempty `name`");
      }
      this.name = name;

      var nest = parameters.nest;
      if (typeof nest !== 'number') {
        throw new TypeError("must have nest");
      }
      if (nest < 0) {
        throw new Error("nest must be non-negative");
      }
      this.nest = nest;

      var myType = parameters.type;
      if (myType) {
        if (!hasOwnProperty(POSSIBLE_TYPES, myType)) {
          throw new TypeError(`unsupported type '${myType}'`);
        }
        this.type = myType;
      }

      if (parameters.remote) this.remote = parameters.remote;
      this.simple = true;
    }

    public valueOf(): ExpressionValue {
      var value = super.valueOf();
      value.name = this.name;
      value.nest = this.nest;
      if (this.type) value.type = this.type;
      if (this.remote) value.remote = this.remote;
      return value;
    }

    public toJS(): ExpressionJS {
      var js = super.toJS();
      js.name = this.name;
      if (this.nest) js.nest = this.nest;
      if (this.type) js.type = this.type;
      return js;
    }

    public toString(): string {
      var str = this.name;
      if (!RefExpression.SIMPLE_NAME_REGEXP.test(str)) {
        str = '{' + str + '}';
      }
      if (this.nest) {
        str = repeat('^', this.nest) + str;
      }
      if (this.type) {
        str += ':' + this.type;
      }
      return '$' + str;
    }

    public getFn(): ComputeFn {
      if (this.nest) throw new Error("can not call getFn on unresolved expression");
      var name = this.name;
      return (d: Datum) => {
        if (hasOwnProperty(d, name)) {
          return d[name];
        } else if (d.$def && hasOwnProperty(d.$def, name)) {
          return d.$def[name];
        } else {
          return null;
        }
      }
    }

    public getJSExpression(datumVar: string): string {
      if (this.nest) throw new Error("can not call getJSExpression on unresolved expression");
      var name = this.name;
      if (datumVar) {
        if (RefExpression.SIMPLE_NAME_REGEXP.test(datumVar)) {
          return datumVar + '.' + name;
        } else {
          return datumVar + "['" + name.replace(/'/g, "\\'") + "']";
        }
      } else {
        return RefExpression.toSimpleName(name);
      }
    }

    public getSQL(dialect: SQLDialect, minimal: boolean = false): string {
      if (this.nest) throw new Error("can not call getSQL on unresolved expression");
      var name = this.name;
      if (name.indexOf('`') !== -1) throw new Error("can not convert to SQL");
      return '`' + name + '`';
    }

    public equals(other: RefExpression): boolean {
      return super.equals(other) &&
        this.name === other.name &&
        this.nest === other.nest;
    }

    public isRemote(): boolean {
      return Boolean(this.remote && this.remote.length);
    }

    public _fillRefSubstitutions(typeContext: FullType, indexer: Indexer, alterations: Alterations): FullType {
      var myIndex = indexer.index;
      indexer.index++;
      var nest = this.nest;

      // Step the parentContext back; once for each generation
      var myTypeContext = typeContext;
      while (nest--) {
        myTypeContext = myTypeContext.parent;
        if (!myTypeContext) throw new Error('went too deep on ' + this.toString());
      }

      // Look for the reference in the parent chain
      var nestDiff = 0;
      while (myTypeContext && !myTypeContext.datasetType[this.name]) {
        myTypeContext = myTypeContext.parent;
        nestDiff++;
      }
      if (!myTypeContext) {
        throw new Error('could not resolve ' + this.toString());
      }

      var myFullType = myTypeContext.datasetType[this.name];

      var myType = myFullType.type;
      var myRemote = myFullType.remote;

      if (this.type && this.type !== myType) {
        throw new TypeError(`type mismatch in ${this.toString()} (has: ${this.type} needs: ${myType})`);
      }

      // Check if it needs to be replaced
      if (!this.type || nestDiff > 0 || String(this.remote) !== String(myRemote)) {
        alterations[myIndex] = new RefExpression({
          op: 'ref',
          name: this.name,
          nest: this.nest + nestDiff,
          type: myType,
          remote: myRemote
        })
      }

      if (myType === 'DATASET') {
        return {
          parent: typeContext,
          type: 'DATASET',
          datasetType: myFullType.datasetType,
          remote: myFullType.remote
        };
      }

      return myFullType;
    }

    public incrementNesting(by: int = 1): RefExpression {
      var value = this.valueOf();
      value.nest = by + value.nest;
      return new RefExpression(value);
    }
  }

  Expression.register(RefExpression);
}

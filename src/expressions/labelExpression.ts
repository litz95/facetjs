module Facet {
  export class LabelExpression extends UnaryExpression {
    static fromJS(parameters: ExpressionJS): LabelExpression {
      var value = UnaryExpression.jsToValue(parameters);
      value.name = parameters.name;
      return new LabelExpression(value);
    }

    public name: string;

    constructor(parameters: ExpressionValue) {
      super(parameters, dummyObject);
      this.name = parameters.name;
      this._ensureOp("label");
      this._checkTypeOfOperand('SET');
      if (!this.name) throw new Error('split must have a name');
      this.type = 'DATASET';
    }

    public valueOf(): ExpressionValue {
      var value = super.valueOf();
      value.name = this.name;
      return value;
    }

    public toJS(): ExpressionJS {
      var js = super.toJS();
      js.name = this.name;
      return js;
    }

    public toString(): string {
      return this.operand.toString() + ".label('" + this.name + "')";
    }

    protected _getFnHelper(operandFn: ComputeFn): ComputeFn {
      var name = this.name;
      return (d: Datum) => {
        var mySet = operandFn(d);
        if (!mySet) return null;
        return mySet.label(name);
      }
    }

    protected _getJSExpressionHelper(operandFnJS: string): string {
      throw `${operandFnJS}.label(${this.name})`;
    }

    protected _getSQLHelper(operandSQL: string, dialect: SQLDialect, minimal: boolean): string {
      return `${operandSQL} AS "${this.name}"`;
    }

    public equals(other: LabelExpression): boolean {
      return super.equals(other) &&
        this.name === other.name;
    }

    protected _specialSimplify(simpleOperand: Expression): Expression {
      if (simpleOperand instanceof AggregateExpression && simpleOperand.fn === 'group') {
        var remoteDatasetLiteral = simpleOperand.operand;
        if (remoteDatasetLiteral instanceof LiteralExpression && remoteDatasetLiteral.isRemote()) {
          var remoteDataset: RemoteDataset = remoteDatasetLiteral.value;

          var newRemoteDataset = remoteDataset.addSplit(simpleOperand.attribute, this.name);
          if (!newRemoteDataset) return null;
          return new LiteralExpression({
            op: 'literal',
            value: newRemoteDataset
          })
        }
      }

      // Try to do this simplification
      // facet('Data1').group('$cut').union(facet('Data2').group('$cut')).label('Cut')
      //    ==>
      // facet('Data1').group('$cut').label('Cut').join(facet('Data2').group('$cut').label('Cut'))
      if (simpleOperand instanceof UnionExpression) {
        var unionLhs = simpleOperand.lhs;
        var unionRhs = simpleOperand.rhs;
        if (unionLhs instanceof AggregateExpression &&
            unionRhs instanceof AggregateExpression &&
            (unionLhs.hasRemote() || unionRhs.hasRemote())) {
          return new JoinExpression({
            op: 'join',
            lhs: new LabelExpression({
              op: 'label',
              name: this.name,
              operand: unionLhs
            }),
            rhs: new LabelExpression({
              op: 'label',
              name: this.name,
              operand: unionRhs
            })
          }).simplify();
        }
      }

      return null;
    }

    public _fillRefSubstitutions(typeContext: FullType, indexer: Indexer, alterations: Alterations): FullType {
      indexer.index++;
      var setFullType = this.operand._fillRefSubstitutions(typeContext, indexer, alterations);
      var newDatasetType: Lookup<FullType> = {};
      
      newDatasetType[this.name] = {
        type: setFullType.type.substring(4), // setFullType will be something like SET/STRING we need to chop off the SET/
        remote: setFullType.remote
      };

      return {
        parent: typeContext,
        type: 'DATASET',
        datasetType: newDatasetType,
        remote: setFullType.remote
      };
    }
  }

  Expression.register(LabelExpression);
}

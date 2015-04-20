module Facet {
  export interface PostProcess {
    (result: any): NativeDataset;
  }

  export interface QueryAndPostProcess<T> {
    query: T;
    postProcess: PostProcess;
  }

  export interface IntrospectPostProcess {
    (result: any): Lookup<AttributeInfo>;
  }

  export interface IntrospectQueryAndPostProcess<T> {
    query: T;
    postProcess: IntrospectPostProcess;
  }

  function getSampleValue(valueType: string, ex: Expression): any {
    switch (valueType) {
      case 'BOOLEAN':
        return true;

      case 'NUMBER':
        return 4;

      case 'NUMBER_RANGE':
        if (ex instanceof NumberBucketExpression) {
          return new NumberRange({ start: ex.offset, end: ex.offset + ex.size });
        } else {
          return new NumberRange({ start: 0, end: 1 });
        }

      case 'TIME':
        return new Date('2015-03-14T00:00:00');

      case 'TIME_RANGE':
        if (ex instanceof TimeBucketExpression) {
          var start = ex.duration.floor(new Date('2015-03-14T00:00:00'), ex.timezone);
          return new TimeRange({ start: start, end: ex.duration.move(start, ex.timezone, 1) });
        } else {
          return new TimeRange({ start: new Date('2015-03-14T00:00:00'), end: new Date('2015-03-15T00:00:00') });
        }

      case 'STRING':
        if (ex instanceof RefExpression) {
          return 'some_' + ex.name;
        } else {
          return 'something';
        }

      default:
        throw new Error("unsupported simulation on: " + valueType);
    }
  }

  export class RemoteDataset extends Dataset {
    static type = 'DATASET';

    static jsToValue(parameters: any): DatasetValue {
      var value = Dataset.jsToValue(parameters);
      if (parameters.requester) value.requester = parameters.requester;
      value.filter = parameters.filter || Expression.TRUE;
      return value;
    }

    public requester: Requester.FacetRequester<any>;
    public mode: string; // raw, total, split (potential aggregate mode)
    public derivedAttributes: ApplyAction[];
    public filter: Expression;
    public split: Expression;
    public defs: DefAction[];
    public applies: ApplyAction[];
    public sort: SortAction;
    public sortOrigin: string;
    public limit: LimitAction;
    public havingFilter: Expression;
    //public fullJoin: RemoteDataset; // ToDo: maybe a good idea to have chain joins
    //public leftJoin: RemoteDataset;

    constructor(parameters: DatasetValue, dummy: Dummy = null) {
      super(parameters, dummyObject);
      this.requester = parameters.requester;
      this.mode = parameters.mode || 'raw';
      this.derivedAttributes = parameters.derivedAttributes || [];
      this.filter = parameters.filter || Expression.TRUE;
      this.split = parameters.split;
      this.defs = parameters.defs;
      this.applies = parameters.applies;
      this.sort = parameters.sort;
      this.sortOrigin = parameters.sortOrigin;
      this.limit = parameters.limit;
      this.havingFilter = parameters.havingFilter;

      if (this.mode !== 'raw') {
        this.defs = this.defs || [];
        this.applies = this.applies || [];

        if (this.mode === 'split') {
          if (!this.split) throw new Error('must have split in split mode');
          if (!this.key) throw new Error('must have key in split mode');
          this.havingFilter = this.havingFilter || Expression.TRUE;
        }
      }
    }

    public valueOf(): DatasetValue {
      var value = super.valueOf();
      if (this.requester) {
        value.requester = this.requester;
      }
      value.mode = this.mode;
      value.derivedAttributes = this.derivedAttributes;
      value.filter = this.filter;
      if (this.split) {
        value.split = this.split;
      }
      if (this.defs) {
        value.defs = this.defs;
      }
      if (this.applies) {
        value.applies = this.applies;
      }
      if (this.sort) {
        value.sort = this.sort;
        value.sortOrigin = this.sortOrigin;
      }
      if (this.limit) {
        value.limit = this.limit;
      }
      if (this.havingFilter) {
        value.havingFilter = this.havingFilter;
      }
      return value;
    }

    public toJS(): DatasetJS {
      var js = super.toJS();
      if (this.requester) {
        js.requester = this.requester;
      }
      if (!this.filter.equals(Expression.TRUE)) {
        js.filter = this.filter.toJS();
      }
      return js;
    }

    public toString(): string {
      switch (this.mode) {
        case 'raw':
          return `RemoteRaw(${this.filter.toString()})`;

        case 'total':
          return `RemoteTotal(${this.applies.length})`;

        case 'split':
          return `RemoteSplit(${this.applies.length})`;

        default :
          return 'Remote()';
      }

    }

    public equals(other: RemoteDataset): boolean {
      return super.equals(other) &&
        this.filter.equals(other.filter);
    }

    public hasRemote(): boolean {
      return true;
    }

    public getRemoteDatasets(): RemoteDataset[] {
      return [this];
    }

    public getRemoteDatasetIds(): string[] {
      return [this.getId()]
    }

    // -----------------

    public canHandleFilter(ex: Expression): boolean {
      throw new Error("must implement canHandleFilter");
    }

    public canHandleTotal(): boolean {
      throw new Error("must implement canHandleTotal");
    }

    public canHandleSplit(ex: Expression): boolean {
      throw new Error("must implement canHandleSplit");
    }

    public canHandleApply(ex: Expression): boolean {
      throw new Error("must implement canHandleApply");
    }

    public canHandleSort(sortAction: SortAction): boolean {
      throw new Error("must implement canHandleSort");
    }

    public canHandleLimit(limitAction: LimitAction): boolean {
      throw new Error("must implement canHandleLimit");
    }

    public canHandleHavingFilter(ex: Expression): boolean {
      throw new Error("must implement canHandleHavingFilter");
    }

    // -----------------

    public makeTotal(): RemoteDataset {
      if (this.mode !== 'raw') return null; // Can only split on 'raw' datasets
      if (!this.canHandleTotal()) return null;

      var value = this.valueOf();
      value.mode = 'total';

      return <RemoteDataset>(new (Dataset.classMap[this.source])(value));
    }

    public addFilter(expression: Expression): RemoteDataset {
      if (!expression.resolved()) return null;

      var value = this.valueOf();
      switch (this.mode) {
        case 'raw':
          if (!this.canHandleFilter(expression)) return null;
          value.filter = value.filter.and(expression).simplify();
          break;

        case 'split':
          if (!this.canHandleHavingFilter(expression)) return null;
          value.havingFilter = value.havingFilter.and(expression).simplify();
          break;

        default:
          return null; // can not add filter in total mode
      }

      return <RemoteDataset>(new (Dataset.classMap[this.source])(value));
    }

    public addSplit(splitExpression: Expression, label: string): RemoteDataset {
      if (this.mode !== 'raw') return null; // Can only split on 'raw' datasets
      if (!this.canHandleSplit(splitExpression)) return null;

      var value = this.valueOf();
      value.mode = 'split';
      value.split = splitExpression;
      value.key = label;

      return <RemoteDataset>(new (Dataset.classMap[this.source])(value));
    }

    public addAction(action: Action): RemoteDataset {
      var expression = action.expression;
      if (action instanceof FilterAction) {
        return this.addFilter(expression);
      }

      var value = this.valueOf();
      if (action instanceof DefAction) {
        if (expression.type !== 'DATASET') return null;

        switch (this.mode) {
          case 'total':
            if (expression instanceof LiteralExpression) {
              var otherDataset: RemoteDataset = expression.value;
              value.derivedAttributes = otherDataset.derivedAttributes;
              value.filter = otherDataset.filter;
              value.defs = value.defs.concat(action);
            } else {
              return null;
            }
            break;

          case 'split':
            // Expect it to be .def('myData', facet('myData').filter(split = ^label)
            var defExpression = action.expression;
            if (defExpression instanceof ActionsExpression &&
              defExpression.actions.length === 1 &&
              defExpression.actions[0].action === 'filter' &&
              defExpression.actions[0].expression.equals(
                this.split.is(new RefExpression({ op: 'ref', name: '^' + this.key, type: this.split.type })))
            ) {
              value.defs = value.defs.concat(action);

            } else {
              return null;
            }
            break;

          default:
            return null; // can not add filter in total mode
        }

      } else if (action instanceof ApplyAction) {
        if (expression.type !== 'NUMBER' && expression.type !== 'TIME') return null;

        if (this.mode === 'raw') {
          value.derivedAttributes = value.derivedAttributes.concat(action);
        } else {
          if (action.name === this.key) return null;
          value.applies = value.applies.concat(action);
        }

      } else if (action instanceof SortAction) {
        if (this.limit) return null; // Can not sort after limit
        if (!this.canHandleSort(action)) return null;
        value.sort = action;

      } else if (action instanceof LimitAction) {
        if (!this.canHandleLimit(action)) return null;
        if (!value.limit || action.limit < value.limit.limit) {
          value.limit = action;
        }

      } else {
        return null;
      }

      return <RemoteDataset>(new (Dataset.classMap[this.source])(value));
    }

    // -----------------

    public simulate(): NativeDataset {
      var datum: Datum = {};

      if (this.mode === 'raw') {
        var attributes = this.attributes;
        for (var attributeName in attributes) {
          if (!hasOwnProperty(attributes, attributeName)) continue;
          datum[attributeName] = getSampleValue(attributes[attributeName].type, null);
        }
      } else {
        if (this.mode === 'split') {
          datum[this.key] = getSampleValue(this.split.type, this.split);
        }

        var applies = this.applies;
        for (var i = 0; i < applies.length; i++) {
          var apply = applies[i];
          datum[apply.name] = getSampleValue(apply.expression.type, apply.expression);
        }
      }

      return new NativeDataset({
        source: 'native',
        data: [datum]
      });
    }

    public getQueryAndPostProcess(): QueryAndPostProcess<any> {
      throw new Error("can not call getQueryAndPostProcess directly");
    }

    public queryValues(): Q.Promise<NativeDataset> {
      if (!this.requester) {
        return <Q.Promise<NativeDataset>>Q.reject(new Error('must have a requester to make queries'));
      }
      try {
        var queryAndPostProcess = this.getQueryAndPostProcess();
      } catch (e) {
        return <Q.Promise<NativeDataset>>Q.reject(e);
      }
      if (!hasOwnProperty(queryAndPostProcess, 'query') || typeof queryAndPostProcess.postProcess !== 'function') {
        return <Q.Promise<NativeDataset>>Q.reject(new Error('no error query or postProcess'));
      }
      return this.requester({ query: queryAndPostProcess.query })
        .then(queryAndPostProcess.postProcess);
    }

    // -------------------------

    public needsIntrospect(): boolean {
      return !this.attributes;
    }

    public getIntrospectQueryAndPostProcess(): IntrospectQueryAndPostProcess<any> {
      throw new Error("can not call getIntrospectQueryAndPostProcess directly");
    }

    public introspect(): Q.Promise<RemoteDataset> {
      if (this.attributes) {
        return Q(this);
      }

      if (!this.requester) {
        return <Q.Promise<RemoteDataset>>Q.reject(new Error('must have a requester to introspect'));
      }
      try {
        var queryAndPostProcess = this.getIntrospectQueryAndPostProcess();
      } catch (e) {
        return <Q.Promise<RemoteDataset>>Q.reject(e);
      }
      if (!hasOwnProperty(queryAndPostProcess, 'query') || typeof queryAndPostProcess.postProcess !== 'function') {
        return <Q.Promise<RemoteDataset>>Q.reject(new Error('no error query or postProcess'));
      }
      var value = this.valueOf();
      var ClassFn = Dataset.classMap[this.source];
      return this.requester({ query: queryAndPostProcess.query })
        .then(queryAndPostProcess.postProcess)
        .then((attributes: Lookup<AttributeInfo>) => {
          value.attributes = attributes;
          return <RemoteDataset>(new ClassFn(value));
        })
    }

    // ------------------------

    private _joinDigestHelper(joinExpression: JoinExpression, action: Action): JoinExpression {
      var ids = action.expression.getRemoteDatasetIds();
      if (ids.length !== 1) throw new Error('must be single dataset');
      if (ids[0] === (<RemoteDataset>(<LiteralExpression>joinExpression.lhs).value).getId()) {
        var lhsDigest = this.digest(joinExpression.lhs, action);
        if (!lhsDigest) return null;
        return new JoinExpression({
          op: 'join',
          lhs: lhsDigest.expression,
          rhs: joinExpression.rhs
        });
      } else {
        var rhsDigest = this.digest(joinExpression.rhs, action);
        if (!rhsDigest) return null;
        return new JoinExpression({
          op: 'join',
          lhs: joinExpression.lhs,
          rhs: rhsDigest.expression
        });
      }
    }

    public digest(expression: Expression, action: Action): Digest {
      if (expression instanceof LiteralExpression) {
        var remoteDataset = expression.value;
        if (remoteDataset instanceof RemoteDataset) {
          var newRemoteDataset = remoteDataset.addAction(action);
          if (!newRemoteDataset) return null;
          return {
            undigested: null,
            expression: new LiteralExpression({
              op: 'literal',
              value: newRemoteDataset
            })
          };
        } else {
          return null;
        }

      } else if (expression instanceof JoinExpression) {
        var lhs = expression.lhs;
        var rhs = expression.rhs;
        if (lhs instanceof LiteralExpression && rhs instanceof LiteralExpression) {
          var lhsValue = lhs.value;
          var rhsValue = rhs.value;
          if (lhsValue instanceof RemoteDataset && rhsValue instanceof RemoteDataset) {
            var actionExpression = action.expression;

            if (action instanceof DefAction) {
              var actionDatasets = actionExpression.getRemoteDatasetIds();
              if (actionDatasets.length !== 1) return null;
              newJoin = this._joinDigestHelper(expression, action);
              if (!newJoin) return null;
              return {
                expression: newJoin,
                undigested: null
              };

            } else if (action instanceof ApplyAction) {
              var actionDatasets = actionExpression.getRemoteDatasetIds();
              if (!actionDatasets.length) return null;
              var newJoin: JoinExpression = null;
              if (actionDatasets.length === 1) {
                newJoin = this._joinDigestHelper(expression, action);
                if (!newJoin) return null;
                return {
                  expression: newJoin,
                  undigested: null
                };
              } else {
                var breakdown = actionExpression.breakdownByDataset('_br_');
                var singleDatasetActions = breakdown.singleDatasetActions;
                newJoin = expression;
                for (var i = 0; i < singleDatasetActions.length && newJoin; i++) {
                  newJoin = this._joinDigestHelper(newJoin, singleDatasetActions[i]);
                }
                if (!newJoin) return null;
                return {
                  expression: newJoin,
                  undigested: new ApplyAction({
                    action: 'apply',
                    name: (<ApplyAction>action).name,
                    expression: breakdown.combineExpression
                  })
                };
              }

            } else {
              return null;
            }
          } else {
            return null;
          }
        } else {
          return null;
        }

      } else {
        throw new Error(`can not digest ${expression.op}`);
      }
    }

  }
}

public enum Stream<A>: NilLiteralConvertible, SequenceType {
	case Nil
	indirect case Cons(A, Memo<Stream>)

	public init<S: SequenceType where S.Generator.Element == A>(sequence: S) {
		self = Stream(generator: sequence.generate())
	}

	public init<G: GeneratorType where G.Element == A>(var generator: G) {
		self = Stream { generator.next() }
	}

	public init(_ f: () -> A?) {
		self = f().map { Stream.Cons($0, Memo { Stream(f) }) } ?? Stream.Nil
	}

	public static func pure(a: A) -> Stream {
		return .Cons(a, Memo(evaluated: .Nil))
	}

	public func analysis<B>(@noescape ifCons ifCons: (A, Memo<Stream>) -> B, @noescape ifNil: () -> B) -> B {
		switch self {
		case let .Cons(first, rest):
			return ifCons(first, rest)
		case .Nil:
			return ifNil()
		}
	}

	public var uncons: (first: A, rest: Memo<Stream>)? {
		return analysis(ifCons: { $0 }, ifNil: { nil })
	}

	public var first: A? {
		return uncons?.first
	}

	public var rest: Memo<Stream> {
		return analysis(ifCons: { $1 }, ifNil: { Memo(evaluated: .Nil) })
	}

	public var isEmpty: Bool {
		return uncons == nil
	}


	public func map<B>(transform: A -> B) -> Stream<B> {
		return analysis(
			ifCons: { .Cons(transform($0), $1.map { $0.map(transform) }) },
			ifNil: const(nil))
	}

	public func flatMap<B>(transform: A -> Stream<B>) -> Stream<B> {
		return analysis(
			ifCons: { transform($0).concat($1.map { $0.flatMap(transform) }) },
			ifNil: const(nil))
	}

	public func concat(other: Memo<Stream>) -> Stream {
		return analysis(
			ifCons: { .Cons($0, $1.map { $0.concat(other.value) }) },
			ifNil: { other.value })
	}

	public func concat(other: Stream) -> Stream {
		return concat(Memo(evaluated: other))
	}


	public func fold<Result>(initial: Result, combine: (A, Memo<Result>) -> Result) -> Result {
		return analysis(
			ifCons: { combine($0, $1.map { $0.fold(initial, combine: combine) }) },
			ifNil: const(initial))
	}

	public static func unfold<State>(state: State, _ unspool: State -> (A, State)?) -> Stream {
		return unspool(state).map { value, next in .Cons(value, Memo { self.unfold(next, unspool) }) } ?? .Nil
	}


	public func zipWith<S: SequenceType>(sequence: S) -> Stream<(A, S.Generator.Element)> {
		return Stream<(A, S.Generator.Element)>.unfold((self, Stream<S.Generator.Element>(sequence: sequence))) {
			guard let (x, xs) = $0.uncons, (y, ys) = $1.uncons else { return nil }
			return ((x, y), (xs.value, ys.value))
		}
	}


	public func take(n: Int) -> Stream {
		return Stream.unfold((Memo(evaluated: self), n)) { stream, n in
			guard let (x, xs) = stream.value.uncons else { return nil }
			return n > 0
				? (x, (xs, n - 1))
				: nil
		}
	}


	public init(nilLiteral: ()) {
		self = .Nil
	}


	public func generate() -> AnyGenerator<A> {
		var current = Memo(evaluated: self)
		return anyGenerator {
			let next = current.value.first
			current = current.value.rest
			return next
		}
	}
}
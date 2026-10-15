// Minimal synchronous host fixture; not an implementation of native scheduling.
public protocol Disposable { func dispose() }
public final class NoopDisposable: Disposable {
    public init() {}
    public func dispose() {}
}
public let EmptyDisposable: Disposable = NoopDisposable()
public final class Subscriber<T, E> {
    let next: ((T) -> Void)?
    let error: ((E) -> Void)?
    let completed: (() -> Void)?
    init(next: ((T) -> Void)?, error: ((E) -> Void)?, completed: (() -> Void)?) {
        self.next = next; self.error = error; self.completed = completed
    }
    public func putNext(_ value: T) { next?(value) }
    public func putError(_ value: E) { error?(value) }
    public func putCompletion() { completed?() }
}
public final class Signal<T, E> {
    let generator: (Subscriber<T, E>) -> Disposable
    public init(_ generator: @escaping (Subscriber<T, E>) -> Disposable) { self.generator = generator }
    public func start(next: ((T) -> Void)? = nil, error: ((E) -> Void)? = nil, completed: (() -> Void)? = nil) -> Disposable {
        return generator(Subscriber(next: next, error: error, completed: completed))
    }
}

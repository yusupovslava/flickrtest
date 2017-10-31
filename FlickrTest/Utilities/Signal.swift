
import Foundation
import Runes

private struct Observer<A> {
    weak var target: AnyObject?
    var selector: ((A) -> Void)
}

open class Signal<A> {
    
    var listeners: [((A) -> Void)] = []
    var currentValue: A?
    fileprivate var observers: [Observer<A>] = []
    
    open func push(_ a: A) {
        self.currentValue = a
        for listener in self.listeners {
            listener(a)
        }
        for observer in observers {
            guard observer.target != nil else { continue }
            observer.selector(a)
        }
    }
    
    open func unpullingListen(_ f: @escaping ((A) -> Void)) {
        self.listeners.append(f)
    }
    
    open func listen(_ f: @escaping ((A) -> Void)) {
        self.unpullingListen(f)
        if let c = currentValue {
            f(c)
        }
    }
    
    open func listen(_ observer: AnyObject, f: @escaping ((A) -> Void)) {
        unpullingListen(observer, f: f)
        if let c = currentValue {
            f(c)
        }
    }
    
    open func unpullingListen(_ observer: AnyObject, f: @escaping ((A) -> Void)) {
        observers.append(Observer(target: observer, selector: f))
    }
    
    open func removeListener(_ observer: AnyObject) {
        observers = observers.filter { $0.target != nil && $0.target !== observer }
    }
    
    @discardableResult
    open func map<B>(_ f: @escaping ((A) -> B)) -> Signal<B> {
        
        let s: Signal<B> = Signal<B>()
        
        s.currentValue = f <*> self.currentValue
        
        self.unpullingListen {(a: A) -> Void in
            s.push(f(a))
        }
        
        return s
    }
    
    @discardableResult
    open func apply<B>(_ signalf: Signal<((A) -> B)>) -> Signal<B> {
        
        let sig = Signal<B>()
        
        sig.currentValue = signalf.currentValue.flatMap {(f: ((A) -> B)) in f <^> self.currentValue}
        
        self.unpullingListen({(a: A) -> Void in
            if let currentFunction = signalf.currentValue {
                sig.push(currentFunction(a))
            }
        })
        
        signalf.unpullingListen({(f: ((A) -> B)) -> Void in
            if let currentValue = self.currentValue {
                sig.push(f(currentValue))
            }
        })
        
        return sig
    }
    
    @discardableResult
    open func merge(_ signal: Signal<A>) -> Signal<A> {
        
        let s: Signal<A> = MkDeadSignal()
        
        if let a = self.currentValue {
            s.currentValue = a
        } else if let a = signal.currentValue {
            s.currentValue = a
        }
        
        self.unpullingListen(s.push)
        signal.unpullingListen(s.push)
        
        return s
    }
    
    @discardableResult
    open func filter(_ f: @escaping ((A) -> Bool)) -> Signal<A> {
        
        let s = Signal<A>()
        
        if let c = self.currentValue {
            if f(c) {
                s.currentValue = self.currentValue
            }
        }
        
        self.unpullingListen {(a: A) -> Void in
            if f(a) {
                s.push(a)
            }
        }
        return s
    }
}

public func resurrect<T>(_ f: inout ((T) -> Void)?) -> Signal<T> {
    let s: Signal<T> = MkDeadSignal()
    f = s.push
    return s
}

public func resurrect<T>(_ f: (((T) -> Void)?) -> Void) -> Signal<T> {
    let s: Signal<T> = MkDeadSignal()
    f(s.push)
    return s
}

public func <^><A, B>(f: @escaping (A) -> B, signal: Signal<A>) -> Signal<B> {
    return signal.map(f)
}

public func <*><A, B>(f: Signal<((A) -> B)>, signal: Signal<A>) -> Signal<B> {
    return map2t((f, signal)).map {$0.0($0.1)}
}

public func pure<A>(_ a: A) -> Signal<A> {
    let s = Signal<A>()
    s.currentValue = a
    return s
}

public func foldp<A, B>(_ s: Signal<A>, start: B, f: @escaping ((B, A) -> B)) -> Signal<B> {
    let b: Signal<B> = pure(start)
    var acc = start
    
    s.unpullingListen {(a: A) -> Void in
        acc = f(acc, a)
        b.push(acc)
    }
    
    return b
}

public func join<A>(_ s: Signal<Signal<A>>) -> Signal<A> {
    
    let ret = Signal<A>()
    var activeSignal = s.currentValue
    ret.currentValue = activeSignal?.currentValue
    
    s.unpullingListen({(s2: Signal<A>) -> Void in
        
        activeSignal?.listeners.removeAll(keepingCapacity: false)
        
        s2.listen(ret.push)
        
        activeSignal = s2
    })
    
    return ret
}

public func >>- <A, B>(signal: Signal<A>, f: @escaping (A) -> Signal<B>) -> Signal<B> {
    return join(f <^> signal)
}

public func -<< <A, B>(f: @escaping (A) -> Signal<B>, signal: Signal<A>) -> Signal<B> {
    return join(f <^> signal)
}

public func MkDeadSignal<A>() -> Signal<A> {
    return Signal<A>()
}

public func MkSignal<A>() -> (Signal<A>, ((A) -> Void)) {
    let s = Signal<A>()
    let f = { (a: A) -> Void in s.push(a) }
    return (s, f)
}

public func limit<T>(_ s: Signal<T>, _ i: TimeInterval) -> Signal<T> {
    let (r, f): (Signal<T>, ((T) -> Void)) = MkSignal()
    r.currentValue = s.currentValue
    
    var lastPing: Date = Date(timeIntervalSince1970: 0)
    
    s.unpullingListen {(t: T) in
        let now = Date()
        if now.timeIntervalSince(lastPing) > i {
            lastPing = now
            f(t)
        }
    }
    
    return r
}

// boilerplate
public func sequence<T, C>(_ optionals: C) -> [T]? where C: Collection, C.Iterator.Element == T? {
    guard !optionals.contains(where: {$0 == nil}) else {
        return nil
    }
    
    return optionals.map {$0!}
}

public func sequence<T, C>(_ signals: C) -> Signal<[T]> where C: Collection, C.Iterator.Element == Signal<T> {
    var current: [T?] = signals.map {$0.currentValue}
    
    var s: Signal<[T]> = MkDeadSignal()
    
    if let ok = sequence(current) {
        s = pure(ok)
    }
    
    signals.enumerated().forEach { idx, signal in
        signal.unpullingListen {(t: T) in
            current[idx] = t
            s.push <*> sequence(current)
        }
    }
    
    return s
}

private func map2<A, B>(_ signalA: Signal<A>, _ signalB: Signal<B>) -> Signal<(A, B)> {
    let (ret, f): (Signal<(A, B)>, (((A, B)) -> Void)) = MkSignal()
    
    if let a = signalA.currentValue,
        let b = signalB.currentValue {
        ret.currentValue = (a, b)
    }
    
    signalA.unpullingListen({
        if let b = signalB.currentValue {
            f(($0, b))
        }
    })
    
    signalB.unpullingListen({
        if let a = signalA.currentValue {
            f((a, $0))
        }
    })
    
    return ret
}

public func map3<A, B, C>(_ signalA: Signal<A>, _ signalB: Signal<B>, _ signalC: Signal<C>) -> Signal<(A, B, C)> {
    let (ret, f): (Signal<(A, B, C)>, (((A, B, C)) -> Void)) = MkSignal()
    
    if let a = signalA.currentValue,
        let b = signalB.currentValue,
        let c = signalC.currentValue {
        ret.currentValue = (a, b, c)
    }
    
    signalA.unpullingListen({
        if let b = signalB.currentValue,
            let c = signalC.currentValue {
            f(($0, b, c))
        }
    })
    
    signalB.unpullingListen({
        if let a = signalA.currentValue,
            let c = signalC.currentValue {
            f((a, $0, c))
        }
    })
    
    signalC.unpullingListen({
        if let a = signalA.currentValue,
            let b = signalB.currentValue {
            f((a, b, $0))
        }
    })
    
    return ret
}

public func map4<A, B, C, D>(_ signalA: Signal<A>, _ signalB: Signal<B>, _ signalC: Signal<C>, _ signalD: Signal<D>) -> Signal<(A, B, C, D)> {
    
    let (ret, f): (Signal<(A, B, C, D)>, (((A, B, C, D)) -> Void)) = MkSignal()
    
    if let a = signalA.currentValue,
        let b = signalB.currentValue,
        let c = signalC.currentValue,
        let d = signalD.currentValue {
        ret.currentValue = (a, b, c, d)
    }
    
    signalA.unpullingListen({
        if let b = signalB.currentValue,
            let c = signalC.currentValue,
            let d = signalD.currentValue {
            f(($0, b, c, d))
        }
    })
    
    signalB.unpullingListen({
        if let a = signalA.currentValue,
            let c = signalC.currentValue,
            let d = signalD.currentValue {
            f((a, $0, c, d))
        }
    })
    
    signalC.unpullingListen({
        if let a = signalA.currentValue,
            let b = signalB.currentValue,
            let d = signalD.currentValue {
            f((a, b, $0, d))
        }
    })
    
    signalD.unpullingListen({
        if let a = signalA.currentValue,
            let b = signalB.currentValue,
            let c = signalC.currentValue {
            f((a, b, c, $0))
        }
    })
    
    return ret
}

public func map5<A, B, C, D, E>(_ signalA: Signal<A>, _ signalB: Signal<B>, _ signalC: Signal<C>, _ signalD: Signal<D>, _ signalE: Signal<E>) -> Signal<(A, B, C, D, E)> {
    
    let (ret, f): (Signal<(A, B, C, D, E)>, (((A, B, C, D, E)) -> Void)) = MkSignal()
    
    if let a = signalA.currentValue,
        let b = signalB.currentValue,
        let c = signalC.currentValue,
        let d = signalD.currentValue,
        let e = signalE.currentValue {
        ret.currentValue = (a, b, c, d, e)
    }
    
    signalA.unpullingListen({
        if let b = signalB.currentValue,
            let c = signalC.currentValue,
            let d = signalD.currentValue,
            let e = signalE.currentValue {
            f(($0, b, c, d, e))
        }
    })
    
    signalB.unpullingListen({
        if let a = signalA.currentValue,
            let c = signalC.currentValue,
            let d = signalD.currentValue,
            let e = signalE.currentValue {
            f((a, $0, c, d, e))
        }
    })
    
    signalC.unpullingListen({
        if let a = signalA.currentValue,
            let b = signalB.currentValue,
            let d = signalD.currentValue,
            let e = signalE.currentValue {
            f((a, b, $0, d, e))
        }
    })
    
    signalD.unpullingListen({
        if let a = signalA.currentValue,
            let b = signalB.currentValue,
            let c = signalC.currentValue,
            let e = signalE.currentValue {
            f((a, b, c, $0, e))
        }
    })
    
    signalE.unpullingListen({
        if let a = signalA.currentValue,
            let b = signalB.currentValue,
            let c = signalC.currentValue,
            let d = signalD.currentValue {
            f((a, b, c, d, $0))
        }
    })
    
    return ret
}

public func map6<A, B, C, D, E, F>(_ signalA: Signal<A>, _ signalB: Signal<B>, _ signalC: Signal<C>, _ signalD: Signal<D>, _ signalE: Signal<E>, _ signalF: Signal<F>) -> Signal<(A, B, C, D, E, F)> {
    
    let (ret, fx): (Signal<(A, B, C, D, E, F)>, (((A, B, C, D, E, F)) -> Void)) = MkSignal()
    
    if let a = signalA.currentValue,
        let b = signalB.currentValue,
        let c = signalC.currentValue,
        let d = signalD.currentValue,
        let e = signalE.currentValue,
        let f = signalF.currentValue {
        ret.currentValue = (a, b, c, d, e, f)
    }
    
    signalA.unpullingListen({
        if let b = signalB.currentValue,
            let c = signalC.currentValue,
            let d = signalD.currentValue,
            let e = signalE.currentValue,
            let f = signalF.currentValue {
            fx(($0, b, c, d, e, f))
        }
    })
    
    signalB.unpullingListen({
        if let a = signalA.currentValue,
            let c = signalC.currentValue,
            let d = signalD.currentValue,
            let e = signalE.currentValue,
            let f = signalF.currentValue {
            fx((a, $0, c, d, e, f))
        }
    })
    
    signalC.unpullingListen({
        if let a = signalA.currentValue,
            let b = signalB.currentValue,
            let d = signalD.currentValue,
            let e = signalE.currentValue,
            let f = signalF.currentValue {
            fx((a, b, $0, d, e, f))
        }
    })
    
    signalD.unpullingListen({
        if let a = signalA.currentValue,
            let b = signalB.currentValue,
            let c = signalC.currentValue,
            let e = signalE.currentValue,
            let f = signalF.currentValue {
            fx((a, b, c, $0, e, f))
        }
    })
    
    signalE.unpullingListen({
        if let a = signalA.currentValue,
            let b = signalB.currentValue,
            let c = signalC.currentValue,
            let d = signalD.currentValue,
            let f = signalF.currentValue {
            fx((a, b, c, d, $0, f))
        }
    })
    
    signalF.unpullingListen({
        if let a = signalA.currentValue,
            let b = signalB.currentValue,
            let c = signalC.currentValue,
            let d = signalD.currentValue,
            let e = signalE.currentValue {
            fx((a, b, c, d, e, $0))
        }
    })
    
    return ret
}

public func map2t<A, B>(_ t: (Signal<A>, Signal<B>)) -> Signal<(A, B)> {
    return map2(t.0, t.1)
}

public func map3t<A, B, C>(_ t: (Signal<A>, Signal<B>, Signal<C>)) -> Signal<(A, B, C)> {
    return map3(t.0, t.1, t.2)
}

public func map4t<A, B, C, D>(_ t: (Signal<A>, Signal<B>, Signal<C>, Signal<D>)) -> Signal<(A, B, C, D)> {
    return map4(t.0, t.1, t.2, t.3)
}

public func map5t<A, B, C, D, E>(_ t: (Signal<A>, Signal<B>, Signal<C>, Signal<D>, Signal<E>)) -> Signal<(A, B, C, D, E)> {
    return map5(t.0, t.1, t.2, t.3, t.4)
}

public func map6t<A, B, C, D, E, F>(_ t: (Signal<A>, Signal<B>, Signal<C>, Signal<D>, Signal<E>, Signal<F>)) -> Signal<(A, B, C, D, E, F)> {
    return map6(t.0, t.1, t.2, t.3, t.4, t.5)
}


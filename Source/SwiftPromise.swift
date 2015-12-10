//
// SwiftPromise.swift
//
// Copyright (c) 2015 Henning Brandt (http://thepurecoder.com/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Foundation

/**
 Bind-Operator.
 Operator for Promises flatMap.
*/
public func >>=<T,R>(p: Promise<T>, f: T -> Promise<R>) -> Promise<R> {
    return p.flatMap(f: f)
}

public class Promise<T> {
    /**
        Type for the final result of the promise.
        It consists of a fulfilled or failed result represented by an Either and
        all callbacks scheduled for the advent of the result.
     */
    private typealias PromiseValue = (Either<T>?, [DeliverBlock])

    /**
        A GCD queue.
        The future block or any method dealing with the promise result is executed in an execution enviroment.
        This enviroment or context is a dispatch queue on which the corresponding computations are performed
     */
    public typealias ExecutionContext = dispatch_queue_t

	/**
        A block of work that can be performed in the background.
        The return value of the block becomes the value of the fulfilled promise.
        If the block throws an error, the promise fails with this error.
	*/
    public typealias BackgroundTask = (() throws -> T)

	/**
        A unit of work. It consists of the execution context on which it should be performed and
        the task itself doing the work with the result of the fulfilled promise.
	*/
    private typealias DeliverBlock = (ExecutionContext, Either<T> -> ())
	
    /**
        The internal result holding the promises value and any callbacks.
        Any code interested in the result must schedule one of the different callbacks or access it via
        - `value`
        - `error`
        - `result`

        fulfillment can be tested via
        - `isFulfilled`
     */
    private var internalValue: PromiseValue = (nil, [])

    /**
        A sempahore to synchronize the critial path concerning fulfillment of the promises result.
        Setting the value can occur from many different threads. The promise must, on a thread safe level, ensure that:
	
        - a promises value can only be set once and after that can never change.
        - any callback scheduled before or after setting the promises value is guaranteed to be invoked with the result
     */
    private let fulfillSemaphore = dispatch_semaphore_create(1)
	
    /**
        The default execution context used for the background task the promise was initialized with and
        any scheduled callback not specifying its own context when scheduled.
    
        - important:
        Exceptions are the three result callbacks:
        - `onComplete()`
        - `onSuccess()`
        - `onFailure()`
	
        These three normally mark endpoints in the value processing and will presumably
        used for interacting with UIKit for updating UI elements etc. So for convenience
        they are performed on the main queue by default.
     */
    private let defaultExecutionContext: ExecutionContext
	
    /**
        Initializer for creating a Promise whose value comes from a block.
     
        Use this if you want the promise to manage asynchronous execution and 
        fulfill itself with the computed value. This mimics more or less the concept of
        a _Future_ combined with a _Promise_.
     
        - parameter executionContext:   The default execution context. The given task will be performed on this queue among others.
                                        Default is a global queue with the default quality of service.
        - parameter task:               A block that gets executed immediately on the given execution context. 
                                        The value returned by this block will fulfill the promise.
    */
    public init(_ executionContext: ExecutionContext = ExecutionContextConstant.DefaultContext, task: BackgroundTask) {
        self.defaultExecutionContext = executionContext
		
        dispatch_async(self.defaultExecutionContext) {
            do {
                let result = try task()
                self.fulfill(.Result(result))
            } catch let error {
                self.fulfill(.Failure(error))
            }
        }
    }
	
    /**
     Initializer for creating a _Promise_ with an already computed value.
     
     The _Promise_ will fulfill itself immediately with a given value.
     You can use this when you have code returning a _Promise_ with a future value, but once you have it you return a cached result
     or some function wants a _Promise_ but you just want to pass an inexpensive value that don't need background computation etc.
     
     - parameter executionContext:   The default execution context.
                                     Default is the main queue.
     - parameter value:              The value to fulfill the _Promise_ with.
    */
	public init(_ executionContext: ExecutionContext = ExecutionContextConstant.MainContext, value: T) {
		self.defaultExecutionContext = executionContext
		self.fulfill(.Result(value))
	}
	
    /**
     Initialier for creating an empty _Promise_.
     
     Use this if your background computation is more complicated and doesn't fit in a block.
     For example when you use libraries requiring own callback blocks or delegate callbacks.
     You can than create an empty _Promise_ return it immediately, performing your work
     and fulfill it manually later via `fulfill()`.
     
     - parameter executionContext:  The default execution context.
                                    Default is a global queue with the default quality of service.
    */
	public init(_ executionContext: ExecutionContext = ExecutionContextConstant.DefaultContext) {
		self.defaultExecutionContext = executionContext
	}
	
    /**
     Method for providing the promise with a value.
     
     Use this to fulfill the _Promise_ with either a result or an error.
     All callbacks already queued up will be called with the given value.
     
     `fulfill()` is thread safe and can safely be called from any thread.
     
     - important:
     A _Promise_ can only be fulfilled once and will have this value over its whole lifetime.
     You can have multiple threads compute a value and call fulfill on the same _Promise_ but only
     the first value will be excepted and set on the _Promise_. All later calls to fulfill are ignored
     and its value will be droped.
     
     - parameter value: The value to set on the _Promise_. This can either be a result or a failure.
                        See `Either` for this.
    */
	public func fulfill(value: Either<T>) {
		dispatch_semaphore_wait(self.fulfillSemaphore, DISPATCH_TIME_FOREVER)
        defer { dispatch_semaphore_signal(self.fulfillSemaphore) }
        
        let (internalResult, blocks) = self.internalValue
        guard internalResult == nil else { return }
        
        self.internalValue = (value, blocks)
        self.executeDeliverBlocks(value)
	}
    
    /**
     Gives back if the promise is fulfilled with either a value or an error.
     
     - returns: true if promise is fulfilled otherwise false
    */
    public func isFulfilled() -> Bool {
        dispatch_semaphore_wait(self.fulfillSemaphore, DISPATCH_TIME_FOREVER)
        defer { dispatch_semaphore_signal(self.fulfillSemaphore) }
        
        let (internalResult, _) = self.internalValue
        return internalResult != nil
    }
    
    /**
     Returns the value the promise was fulfilled with.
     
     A Promise can either be fulfilled with a result or an error,
     so value returns an Either.
     
     - returns: An Either with the Promises result/error or nil if the Promise is not fulfilled yet
    */
    public func value() -> Either<T>? {
        dispatch_semaphore_wait(self.fulfillSemaphore, DISPATCH_TIME_FOREVER)
        defer { dispatch_semaphore_signal(self.fulfillSemaphore) }
        
        let (internalResult, _) = self.internalValue
        return internalResult
    }
    
    /**
     Returns the Promises result if there is one.
     
     - returns: The Promises result if there is one or nil if the Promise is not fulfilled yet
                or is fulfilled with an error.
    */
    public func result() -> T? {
        dispatch_semaphore_wait(self.fulfillSemaphore, DISPATCH_TIME_FOREVER)
        defer { dispatch_semaphore_signal(self.fulfillSemaphore) }
        
        let (internalResult, _) = self.internalValue
        guard let result = internalResult else {
            return nil
        }
        
        switch result {
        case .Result(let r):
            return r
        case .Failure:
            return nil
        }
    }
    
    /**
     Returns the Promises error if there is one.
     
     - returns: The Promises error if there is one or nil if the Promise is not fulfilled yet
                or is fulfilled with a result.
     */
    public func error() -> ErrorType? {
        dispatch_semaphore_wait(self.fulfillSemaphore, DISPATCH_TIME_FOREVER)
        defer { dispatch_semaphore_signal(self.fulfillSemaphore) }
        
        let (internalResult, _) = self.internalValue
        guard let result = internalResult else {
            return nil
        }
        
        switch result {
        case .Result:
            return nil
        case .Failure(let error):
            return error
        }
    }
	
    /**
     Callback triggered at fulfillment of the Promise.
     
     Registers a callback interested in general fulfillment of the Promise with eiter a result or an error.
     
     - parameter context: dispatch_queue on which to perform the block. Default is the main queue.
     - parameter f: The block scheduled for fulfillment. Takes the value of the Promise as argument.
    */
	public func onComplete(context: ExecutionContext = ExecutionContextConstant.MainContext, f: Either<T> -> ()) -> Promise<T> {
		self.enqueueDeliverBlock({ f($0) }, context)
		return self
	}

    /**
     Callback triggered at fulfillment of the Promise.
     
     Registers a callback interested in fulfillment of the Promise with a result.
     
     - parameter context: dispatch_queue on which to perform the block. Default is the main queue.
     - parameter f: The block scheduled for fulfillment. Takes the result of the Promise as argument.
     */
	public func onSuccess(context: ExecutionContext = ExecutionContextConstant.MainContext, f: (T) -> ()) -> Promise<T> {
		self.enqueueDeliverBlock({
			switch $0 {
			case .Result(let result):
                f(result)
			case .Failure:
                break
			}
        }, context)
		
		return self
	}
	
    /**
     Callback triggered at fulfillment of the Promise.
     
     Registers a callback interested in fulfillment of the Promise with an error.
     
     - parameter context: dispatch_queue on which to perform the block. Default is the main queue.
     - parameter f: The block scheduled for fulfillment. Takes the value of the Promise as argument.
                    Can throw an error wich will be carried up the Promise chain.
     */
	public func onFailure(context: ExecutionContext = ExecutionContextConstant.MainContext, f: ErrorType -> ()) -> Promise<T> {
		self.enqueueDeliverBlock({
			switch $0 {
			case .Result:
                break
			case .Failure(let error):
                f(error)
			}
        }, context)
		
		return self
	}
	
    /**
     Map a Promise of type A to a Promise of type B.
     
     Registers a callback on fulfillment, which will map the Promise to a Promise of another type.
     
     - parameter context: dispatch queue on which to perform the block.
                          Default is the default queue the Promise was initialized with.
     - parameter f: The block scheduled for fulfillment. Takes the result of the Promise as an argument and returning another result.
                    Can throw an error wich will be carried up the Promise chain.
     
     - returns: A Promise wrapping the value produced by f
     */
	public func map<R>(context: ExecutionContext = ExecutionContextConstant.PlaceHolderContext, f: T throws -> R) -> Promise<R> {
		let promise = Promise<R>(self.validContext(context))
		
		self.enqueueDeliverBlock({
			switch $0 {
			case .Failure(let error):
                promise.fulfill(.Failure(error))
			case .Result(let result):
				do {
					let mappedResult = try f(result)
					promise.fulfill(.Result(mappedResult))
				} catch let error {
					promise.fulfill(.Failure(error))
				}
			}
        }, context)
		
		return promise
	}
	
    /**
     Returning a second Promise produced with the value of self by a given function f.
     
     Monadic bind-function. Can among others be used to sequence Promises.
     Because f, returning the second Promise, is called with the result of the first Promise,
     the execution of f is delayed until the first Promise is fulfilled.
     
     Has also an operator: >>=
     
     - parameter context: dispatch queue on which to perform the block. 
                          Default is the default queue the Promise was initialized with.
     - parameter f: The block scheduled for fulfillment. Takes the value of the Promise as argument and returning a second Promise.
                    Can throw an error wich will be carried up the Promise chain.
     
     - returns: The Promise produced by f
    */
	public func flatMap<R>(context: ExecutionContext = ExecutionContextConstant.PlaceHolderContext, f: T throws -> Promise<R>) -> Promise<R> {
		let ctx = self.validContext(context)
		let placeholder = Promise<R>(ctx)
		
		self.enqueueDeliverBlock({
			switch $0 {
			case .Failure(let error):
				placeholder.fulfill(.Failure(error))
			case .Result(let result):
				do {
                    // The f function can't produce a Promise until the current promise is fulfilled
                    // but it is required to return a promise immediately for this reason we introduce
                    // a placeholder which completes simultaneously with the promise produced by f.
					let promise = try f(result)
					promise.onComplete(ctx) { placeholder.fulfill($0) }
				} catch let error {
					placeholder.fulfill(.Failure(error))
				}
			}
        }, context)
		
		return placeholder
	}
	
	public func filter(context: ExecutionContext = ExecutionContextConstant.PlaceHolderContext, f: T throws -> Bool) -> Promise<T> {
		let promise = Promise<T>(self.validContext(context))
		
		self.enqueueDeliverBlock({
			switch $0 {
			case .Failure:
				promise.fulfill($0)
			case .Result(let result):
				do {
					let passedFilter = try f(result)
					if passedFilter {
						promise.fulfill($0)
					} else {
						promise.fulfill(.Failure(Error.FilterNotPassed))
					}
				} catch let error {
					promise.fulfill(.Failure(error))
				}
			}
        }, context)
		
		return promise
	}
    
    
    public class func collect<R>(promises: [Promise<R>]) -> Promise<[R]> {
        func comb(acc: Promise<[R]>, elem: Promise<R>) -> Promise<[R]> {
            return elem >>= { x in
                acc >>= { xs in
                    var _xs = xs
                    _xs.append(x)
                    return Promise<[R]>(value: _xs)
                }
            }
        }
        
        return promises.reduce(Promise<[R]>(value: []), combine: comb)
    }
    
    public class func select<R>(promises: [Promise<R>], context: ExecutionContext = ExecutionContextConstant.DefaultContext)
        -> Promise<(Promise<R>, [Promise<R>])>
    {
        let promise = Promise<(Promise<R>, [Promise<R>])>(context)
        
        for p in promises {
            p.onComplete { _ in
                let result = (p, promises.filter { $0 !== p } )
                promise.fulfill(.Result(result))
            }
        }
        
        return promise
    }
}

extension Promise {
    private func enqueueDeliverBlock(block: Either<T> -> (), _ executionContext: ExecutionContext?) {
        dispatch_semaphore_wait(self.fulfillSemaphore, DISPATCH_TIME_FOREVER)
        defer { dispatch_semaphore_signal(self.fulfillSemaphore) }
        
        let ctx = executionContext != nil ? executionContext! : self.defaultExecutionContext
        
        var (result, deliverBlocks) = self.internalValue
        deliverBlocks.append((ctx, block))
        self.internalValue = (result, deliverBlocks)
        
        if let _result = result {
            self.executeDeliverBlocks(_result)
        }
    }
    
    private func executeDeliverBlocks(value: Either<T>) {
        var (_, deliverBlocks) = self.internalValue
        
        for deliverBlock in deliverBlocks {
            let (executionContext, block) = deliverBlock
            dispatch_async(executionContext) {
                block(value)
            }
        }
        
        deliverBlocks.removeAll()
    }
    
    private func validContext(context: ExecutionContext) -> ExecutionContext {
        guard context.isEqual(ExecutionContextConstant.PlaceHolderContext) else {
            return self.defaultExecutionContext
        }
        
        return context
    }
}

private struct ExecutionContextConstant {
	static let MainContext = dispatch_get_main_queue()
	static let DefaultContext = dispatch_get_global_queue(Int(QOS_CLASS_DEFAULT.rawValue), 0)
	static let PlaceHolderContext = dispatch_queue_create("com.promise.placeHolder", DISPATCH_QUEUE_CONCURRENT)
}


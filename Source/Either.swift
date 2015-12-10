//
// Either.swift
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

public enum Either<T> {
	case Result(T)
	case Failure(ErrorType)
	
	var hasResult: Bool {
		switch self {
		case .Result:
			return true
		case .Failure:
			return false
		}
	}
	
	var isFailure: Bool {
		return !self.hasResult
	}
	
	var result: T? {
		switch self {
		case .Result(let result):
			return result
		case Failure:
			return nil
		}
	}
	
	var error: ErrorType? {
		switch self {
		case .Result:
			return nil
		case Failure(let error):
			return error
		}
	}
}

extension Either: CustomStringConvertible {
	public var description: String {
		switch self {
		case .Result:
			return "Either.Result"
		case .Failure:
			return "Either.Failure"
		}
	}
}

extension Either: CustomDebugStringConvertible {
	public var debugDescription: String {
		switch self {
		case .Result(let value):
			return "Either.Result: \(value)"
		case .Failure(let error):
			return "Either.Failure: \(error)"
		}
	}
}
//
// WeatherService.swift
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
import SwiftPromise

class WeatherService {
    enum Error: ErrorType {
        case MalformedURL
        case MalformedJSON
    }
    
    class func weatherForCity(city: String) -> Promise<(String?, [NSDictionary])> {
        return performQuery("select * from weather.forecast where woeid in (select woeid from geo.places(1) where text='\(city)')")
            .map { dic in
                let query = dic["query"] as? NSDictionary
                let results = query?["results"] as? NSDictionary
                let channel = results?["channel"] as? NSDictionary
                let item = channel?["item"] as? NSDictionary
                let title = channel?["description"] as? String
            
                guard let forecast = item?["forecast"] as? [NSDictionary] else {
                    throw Error.MalformedJSON
                }
            
                return (title, forecast)
            }
    }
    
    class func citiesWithName(name: String) -> Promise<(String, [(String, Int)])> {
        return performQuery("select woeid, name, country, admin1 from geo.places where text = '\(name)'")
            .map { dic in
                let query = dic["query"] as? NSDictionary
                let results = query?["results"] as? NSDictionary
                let place = results?["place"] as? NSArray
                NSLog("%@", dic)
                guard let p = place else {
                    throw Error.MalformedJSON
                }
                
                var result = [(String, Int)]()
                for city in p {
                    let country = city["country"] as? NSDictionary
                    let admin = city["admin1"] as? NSDictionary
                    let countryName = country?["content"] as? String
                    let adminName = admin?["content"] as? String
                    let name = city["name"] as? String
                    let woeid = city["woeid"] as? String
                    
                    guard let cname = countryName, aname = adminName, n = name, id = woeid else {
                        throw Error.MalformedJSON
                    }
                    
                    result.append(("\(n), \(aname), \(cname)", Int(id)!))
                }
                
                return (name, result)
            }
    }
    
    private class func performQuery(query: String) -> Promise<NSDictionary> {
        let urlStr = "https://query.yahooapis.com/v1/public/yql?q=\(query)&format=json&env=store://datatables.org Falltableswithkeys".stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLQueryAllowedCharacterSet())
        
        guard let url = urlStr else {
            let promise = Promise<NSDictionary>()
            promise.fulfill(.Failure(Error.MalformedURL))
            return promise
        }
        
        let promise = Promise<NSData>()

        let session = NSURLSession.sharedSession()
        let weatherTask = session.dataTaskWithURL(NSURL(string: url)!, completionHandler: { data, response, error in
            if let err = error {
                promise.fulfill(.Failure(err))
                return
            }
            
            if let json = data {
                promise.fulfill(.Result(json))
            }
        })
        weatherTask.resume()
        
        return promise.map { data in
            return try NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments) as! NSDictionary
        }
    }
}
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
    enum Error: ErrorProtocol {
        case malformedURL
        case malformedJSON
    }
    
    class func fetchWeather(forCity city: String) -> Promise<(String?, Dictionary<String, AnyObject>)> {
        return performQuery(query: "select * from weather.forecast where woeid in (select woeid from geo.places(1) where text='\(city)')")
            .map { dic in
                
                guard   let query = dic["query"] as? Dictionary<String, AnyObject>,
                        let results = query["results"] as? Dictionary<String, AnyObject>,
                        let channel = results["channel"] as? Dictionary<String, AnyObject>,
                        let item = channel["item"] as? Dictionary<String, AnyObject>,
                        let title = channel["description"] as? String,
                        let forecast = item["forecast"] as? Dictionary<String, AnyObject>
                else {
                    throw Error.malformedJSON
                }
            
                return (title, forecast)
            }
    }
    
    class func fetchCities(withName name: String) -> Promise<(String, [(String, Int)])> {
        return performQuery(query: "select woeid, name, country, admin1 from geo.places where text = '\(name)'")
            .map { dic in
                
                guard   let query = dic["query"] as? Dictionary<String, AnyObject>,
                        let results = query["results"] as? Dictionary<String, AnyObject>,
                        let places = results["place"] as? Array<Dictionary<String, AnyObject>>
                else {
                    throw Error.malformedJSON
                }
        
                var result = [(String, Int)]()
                for place in places {
                    if  let country = place["country"] as? Dictionary<String, AnyObject>,
                        let admin = place["admin1"] as? Dictionary<String, AnyObject>,
                        let countryName = country["content"] as? String,
                        let adminName = admin["content"] as? String,
                        let name = place["name"] as? String,
                        let woeid = place["woeid"] as? String
                    {
                        result.append(("\(name), \(adminName), \(countryName)", Int(woeid)!))
                    }
                    else {
                       throw Error.malformedJSON
                    }
                }
                
                return (name, result)
            }
    }
    
    private class func performQuery(query: String) -> Promise<Dictionary<String, AnyObject>> {
        let urlStr = "https://query.yahooapis.com/v1/public/yql?q=\(query)&format=json&env=store://datatables.org Falltableswithkeys" as NSString
        let escapedUrlStr = urlStr.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)

        guard let url = escapedUrlStr else {
            let promise = Promise<Dictionary<String, AnyObject>>()
            promise.fulfill(.failure(Error.malformedURL))
            return promise
        }
        
        let promise = Promise<Data>()

        let session = URLSession.shared
        let weatherTask = session.dataTask(with: URL(string: url)!, completionHandler: { data, response, error in
            if let err = error {
                promise.fulfill(.failure(err))
                return
            }
            
            if let json = data {
                promise.fulfill(.result(json))
            }
        })
        weatherTask.resume()
        
        return promise.map { data in
            return try JSONSerialization.jsonObject(with: data, options: .allowFragments) as! Dictionary<String, AnyObject>
        }
    }
}

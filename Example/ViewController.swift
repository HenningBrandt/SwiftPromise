//
// ViewController.swift
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
import UIKit
import SwiftPromise

class ViewController: UITableViewController {
    var forecasts: [NSDictionary] = []
    var spinner = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
    var searchController: UISearchController!
    var currentPlace: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        refreshControl = UIRefreshControl()
        refreshControl!.addTarget(self, action: "reload", forControlEvents: .ValueChanged)
                
        reloadWeatherDataForCity("Berlin")
        
        // SearchController
        let resultController = SearchController()
        resultController.master = self
        self.searchController = UISearchController(searchResultsController: resultController)
        self.searchController.searchResultsUpdater = resultController
        self.searchController.obscuresBackgroundDuringPresentation = true
        self.searchController.searchBar.placeholder = "Search City"
        self.tableView.tableHeaderView = self.searchController.searchBar
    }
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return forecasts.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        return tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
    }
    
    override func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        let forecast = forecasts[indexPath.row]
        if let day = forecast["day"], text = forecast["text"] {
            cell.textLabel?.text = day as? String
            cell.detailTextLabel?.text = text as? String
        }
    }
    
    func reloadWeatherDataForCity(city: String) {
        self.dismissViewControllerAnimated(true) {
            
        }
        navigationItem.titleView = spinner
        spinner.startAnimating()
        
        WeatherService.weatherForCity(city).onSuccess { [weak self] in
            self?.spinner.stopAnimating()
            self?.navigationItem.titleView = nil;
            self?.refreshControl?.endRefreshing()
            
            let (title, forecast) = $0
            self?.title = title
            self?.forecasts = forecast
            self?.tableView.reloadData()
            self?.currentPlace = city
            
            self?.searchController.searchBar.text = nil
        }
    }
    
    func reload() {
        if let city = self.currentPlace {
            reloadWeatherDataForCity(city)
        }
    }
}


/// Copyright (c) 2019 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import RxSwift
import RxCocoa
import MapKit
import CoreLocation

typealias Weather = ApiController.Weather

protocol WeatherCachable {
    func cacheWeather(_ w: Weather, with key: String)
}

class ViewController: UIViewController, WeatherCachable {
    
    func cacheWeather(_ w: Weather, with key: String) {
        cache[key] = w
    }
    
    @IBOutlet weak var keyButton: UIButton!
    @IBOutlet weak var geoLocationButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var searchCityName: UITextField!
    @IBOutlet weak var tempLabel: UILabel!
    @IBOutlet weak var humidityLabel: UILabel!
    @IBOutlet weak var iconLabel: UILabel!
    @IBOutlet weak var cityNameLabel: UILabel!
    
    private let bag = DisposeBag()
    private let locationManager = CLLocationManager()
    
    private var cache = [String: Weather]()
    
    var keyTextField: UITextField?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        Reachability.shared.monitorReachabilityChanges()
        Reachability.shared.connected
            .skip(1)
            .distinctUntilChanged()
            .subscribe(onNext: { value in
                print("IS CONNECTED? :")
                print(value)
            })
            .disposed(by: bag)
        
        style()
        
        keyButton.rx.tap
            .subscribe(onNext: {
                self.requestKey()
            })
            .disposed(by:bag)
        
        let currentLocation = locationManager.rx.didUpdateLocations
            .map() { locations in locations[0] }
            .filter() { location in
                return location.horizontalAccuracy == kCLLocationAccuracyNearestTenMeters
        }
        
        let geoInput = geoLocationButton.rx.tap
            .do(onNext: {
                self.locationManager.requestWhenInUseAuthorization()
                self.locationManager.startUpdatingLocation()
                
                self.searchCityName.text = "Current Location"
            })
        
        let geoLocation = geoInput.flatMap {
            return currentLocation.take(1)
        }
        
        let geoSearch = geoLocation.flatMap() { location in
            return ApiController.shared.currentWeather(at: location.coordinate)
                .catchErrorJustReturn(.empty)
        }
        
        /**
         Retry handler
         */
        let maxAttempts = 4
        let retryHandler: (Observable<Error>) -> Observable<Int> = { e in
            return e.enumerated().flatMap { attempt, error -> Observable<Int> in
                // attempts left
                if attempt >= maxAttempts - 1 {
                    return Observable.error(error)
                    // if api key isn't valid
                } else if let casted = error as? ApiController.ApiError, casted == .invalidKey {
                    /// key input
                    DispatchQueue.main.async { [weak self] in
                        self?.requestKey()
                    }
                    return ApiController.shared.apiKey
                        .filter { !$0.isEmpty }
                        .map { _ in 1 }
                    // if no internet connection
                } else if (error as NSError).code == -1009 {
                    return Reachability.shared.connected
                        .distinctUntilChanged()
                        .filter { $0 == true }
                        .map { _ in 1 }
                }
                // retry delay based on current attempt, max 4
                print("== retrying after \(attempt + 1) seconds ==")
                return Observable<Int>
                    .timer(Double(attempt + 1), scheduler: MainScheduler.instance)
                    .take(1)
            }
        }
        
        
        
        
        let searchInput = searchCityName.rx.controlEvent(.editingDidEndOnExit)
            .map { self.searchCityName.text ?? "" }
            .filter { !$0.isEmpty }
        
        let textSearch = searchInput.flatMap { text in
            return ApiController.shared.currentWeather(city: text)
                .materialize() // [- debug
                .do(onNext: { event in
                    print("📱")
                    print(event)
                    switch event {
                    case .error(let error):
                        print(error)
                        break
                    case _:
                        break
                    }
                })
                .dematerialize() // debug -]
                .cache(key: text, displayErrorIn: self, cachable: self)
                .retryWhen(retryHandler)
                .catchError { error in
                    guard let cachedWeather = self.cache[text] else {
                        return Observable.just(.empty)
                    }
                    return Observable.just(cachedWeather)
            }
        }
        
        let search = Observable.merge(geoSearch, textSearch)
            .asDriver(onErrorJustReturn: .empty)
        
        let running = Observable.merge(searchInput.map { _ in true },
                                       geoInput.map { _ in true },
                                       search.map { _ in false }.asObservable())
            .startWith(true)
            .asDriver(onErrorJustReturn: false)
        
        search.map { "\($0.temperature)° C" }
            .drive(tempLabel.rx.text)
            .disposed(by:bag)
        
        search.map { $0.icon }
            .drive(iconLabel.rx.text)
            .disposed(by:bag)
        
        search.map { "\($0.humidity)%" }
            .drive(humidityLabel.rx.text)
            .disposed(by:bag)
        
        search.map { $0.cityName }
            .drive(cityNameLabel.rx.text)
            .disposed(by:bag)
        
        running.skip(1).drive(activityIndicator.rx.isAnimating).disposed(by:bag)
        running.drive(tempLabel.rx.isHidden).disposed(by:bag)
        running.drive(iconLabel.rx.isHidden).disposed(by:bag)
        running.drive(humidityLabel.rx.isHidden).disposed(by:bag)
        running.drive(cityNameLabel.rx.isHidden).disposed(by:bag)
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        Appearance.applyBottomLine(to: searchCityName)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func requestKey() {
        func configurationTextField(textField: UITextField!) {
            self.keyTextField = textField
        }
        
        let alert = UIAlertController(title: "Api Key",
                                      message: "Add the api key:",
                                      preferredStyle: UIAlertController.Style.alert)
        
        alert.addTextField(configurationHandler: configurationTextField)
        
        alert.addAction(UIAlertAction(title: "Ok", style: .default) { [weak self] _ in
            ApiController.shared.apiKey.onNext(self?.keyTextField?.text ?? "")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.destructive))
        
        self.present(alert, animated: true)
    }
    
    // MARK: - Style
    
    private func style() {
        view.backgroundColor = UIColor.aztec
        searchCityName.textColor = UIColor.ufoGreen
        tempLabel.textColor = UIColor.cream
        humidityLabel.textColor = UIColor.cream
        iconLabel.textColor = UIColor.cream
        cityNameLabel.textColor = UIColor.cream
    }
}


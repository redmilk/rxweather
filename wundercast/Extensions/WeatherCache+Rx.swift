//
//  WeatherCache+Rx.swift
//  Wundercast
//
//  Created by Danyl Timofeyev on 28.10.2020.
//  Copyright © 2020 Ray Wenderlich. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

// weather cache
extension ObservableType where Element == Weather {

    func cache(key: String, displayErrorIn viewController: UIViewController, cachable: WeatherCachable) -> Observable<Element> {
    return self
      .observeOn(MainScheduler.instance)
      .do(onNext: { data in
        cachable.cacheWeather(data, with: key)
      },
      onError: { e in
        guard let e = e as? ApiController.ApiError else {
          InfoView.showIn(viewController: viewController, message: "An error occurred")
          return
        }
        switch e {
          case .cityNotFound:
          InfoView.showIn(viewController: viewController, message: "City Name is invalid")
          case .serverFailure:
            InfoView.showIn(viewController: viewController, message: "Server error")
          case .invalidKey:
            InfoView.showIn(viewController: viewController, message: "Key is invalid")
        }
    })
  }
}

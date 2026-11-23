import CoreLocation
import RecorderCore

/// The phone's own position while recording. "While using" permission is
/// enough: updates start with the app open and continue in the background.
final class PhoneGPS: NSObject, CLLocationManagerDelegate {
    var onFix: ((GPSFix) -> Void)?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            onFix?(GPSFix(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                          speedMS: loc.speed >= 0 ? loc.speed : nil,
                          course: loc.course >= 0 ? loc.course : nil,
                          hAccM: loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil,
                          utc: loc.timestamp))
        }
    }
}

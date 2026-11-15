import Foundation
import SwiftUI
import Combine
import AppTrackingTransparency
import AdSupport
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// Returns the top-most view controller for presenting ads.
func topViewController() -> UIViewController? {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first?.rootViewController else { return nil }
    var vc = root
    while let presented = vc.presentedViewController { vc = presented }
    return vc
}

/// Central ad coordinator for S.W.I.S.H.
///
/// Uses Google AdMob when the SDK is linked (in Xcode: File > Add Package
/// Dependencies > "google-mobile-ads-sdk"). Without the SDK it runs
/// clearly-labeled SIMULATED ads so the full game flow stays testable.
///
/// Uses the production ad units from Michael's AdMob account (created
/// 2026-10-19); the AdMob app ID lives in Info.plist.
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    // MARK: Production ad units (AdMob account mzaras11@gmail.com)
    private let rewardedAdUnitID = "ca-app-pub-9461680459080238/4229002468"
    private let interstitialAdUnitID = "ca-app-pub-9461680459080238/1821817623"
    let bannerAdUnitID = "ca-app-pub-9461680459080238/6802360769"

    @Published var rewardedReady = false
    @Published var showingMockAd = false
    @Published var mockAdTitle = "Simulated ad"

    /// True only once a real banner ad has actually loaded. The banner
    /// strip exists on screen only while this is true (Michael's rule,
    /// 2026-10-19: show the ad only when there is an actual ad).
    @Published var bannerLoaded = false
    private var bannerHasLoaded = false

    #if canImport(GoogleMobileAds)
    private var rewardedAd: GADRewardedAd?
    private var interstitialAd: GADInterstitialAd?
    #endif

    var adsAreReal: Bool {
        #if canImport(GoogleMobileAds)
        return true
        #else
        return false
        #endif
    }

    private var adFlowStarted = false

    private override init() {
        super.init()
        // Ads are NOT loaded here. Guideline 5.1.2(i): the App Tracking
        // Transparency request must come first — see beginAdFlow().
    }

    /// Entry point for the ad flow, called once from the app's init.
    /// Presents the ATT permission request (after a short settle delay so
    /// the first screen is on display); only after the user decides does
    /// the ads SDK start and the first ads load. A "no" still gets ads —
    /// they are simply not personalized.
    func beginAdFlow() {
        guard !adFlowStarted else { return }
        adFlowStarted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if #available(iOS 14, *) {
                ATTrackingManager.requestTrackingAuthorization { _ in
                    DispatchQueue.main.async { AdManager.shared.startAds() }
                }
            } else {
                AdManager.shared.startAds()
            }
        }
    }

    private func startAds() {
        #if canImport(GoogleMobileAds)
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        #endif
        loadRewarded()
        loadInterstitial()
    }

    // MARK: - Rewarded (watch ad -> earn hint)

    func loadRewarded() {
        #if canImport(GoogleMobileAds)
        GADRewardedAd.load(withAdUnitID: rewardedAdUnitID, request: GADRequest()) { [weak self] ad, _ in
            DispatchQueue.main.async {
                self?.rewardedAd = ad
                self?.rewardedReady = (ad != nil)
            }
        }
        #else
        rewardedReady = true // mock ads are always "ready"
        #endif
    }

    /// Presents a rewarded ad. `completion(true)` only when the reward was earned.
    func showRewarded(from root: UIViewController, completion: @escaping (Bool) -> Void) {
        #if canImport(GoogleMobileAds)
        guard let ad = rewardedAd else { completion(false); return }
        rewardedReady = false
        ad.present(fromRootViewController: root) { [weak self] in
            completion(true)
            self?.loadRewarded()
        }
        #else
        mockAdTitle = "Simulated rewarded ad"
        showingMockAd = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.showingMockAd = false
            completion(true)
        }
        #endif
    }

    // MARK: - Interstitial (between games)

    func loadInterstitial() {
        #if canImport(GoogleMobileAds)
        GADInterstitialAd.load(withAdUnitID: interstitialAdUnitID, request: GADRequest()) { [weak self] ad, _ in
            DispatchQueue.main.async { self?.interstitialAd = ad }
        }
        #endif
    }

    func showInterstitial(from root: UIViewController) {
        #if canImport(GoogleMobileAds)
        if let ad = interstitialAd {
            ad.present(fromRootViewController: root)
            loadInterstitial()
        }
        #else
        mockAdTitle = "Simulated interstitial ad"
        showingMockAd = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.showingMockAd = false
        }
        #endif
    }

    // MARK: - Banner

    #if canImport(GoogleMobileAds)
    private weak var bannerView: GADBannerView?

    func makeBanner(delegate: GADBannerViewDelegate?) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = bannerAdUnitID
        banner.delegate = delegate
        bannerView = banner
        banner.load(GADRequest())
        return banner
    }

    /// A real banner ad arrived — the strip may show.
    func noteBannerLoaded() {
        bannerHasLoaded = true
        bannerLoaded = true
    }

    /// A banner load failed (for example no ad available). Before the
    /// first success the strip stays hidden; afterwards the on-screen ad
    /// is kept. Either way, retry later so one empty moment does not
    /// disable banners for the whole session.
    func noteBannerFailed() {
        if !bannerHasLoaded { bannerLoaded = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            self?.bannerView?.load(GADRequest())
        }
    }
    #endif
}

#if canImport(GoogleMobileAds)
/// SwiftUI wrapper for an AdMob banner.
struct BannerAdView: UIViewRepresentable {
    func makeUIView(context: Context) -> GADBannerView {
        let banner = AdManager.shared.makeBanner(delegate: context.coordinator)
        banner.rootViewController = topViewController()
        return banner
    }
    func updateUIView(_ uiView: GADBannerView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, GADBannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            AdManager.shared.noteBannerLoaded()
        }
        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            AdManager.shared.noteBannerFailed()
        }
    }
}
#endif

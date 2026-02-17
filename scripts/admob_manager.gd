extends Node
# AdMob Manager — Poing Studios v4 (Godot 4.4+)
# Autoload: Project → Project Settings → Autoload → "AdMobManager"

# ===== PRELOAD KLAS =====
const AdViewClass          = preload("res://addons/admob/src/api/AdView.gd")
const AdRequestClass       = preload("res://addons/admob/src/api/core/AdRequest.gd")
const AdSizeClass          = preload("res://addons/admob/src/api/core/AdSize.gd")
const AdPositionClass      = preload("res://addons/admob/src/api/core/AdPosition.gd")
const AdListenerClass      = preload("res://addons/admob/src/api/listeners/AdListener.gd")
const MobileAdsClass       = preload("res://addons/admob/src/api/MobileAds.gd")
const InterstitialAdLoaderClass       = preload("res://addons/admob/src/api/InterstitialAdLoader.gd")
const InterstitialAdLoadCallbackClass = preload("res://addons/admob/src/api/listeners/InterstitialAdLoadCallback.gd")
const FullScreenContentCallbackClass  = preload("res://addons/admob/src/api/listeners/FullScreenContentCallback.gd")
const RewardedAdLoaderClass           = preload("res://addons/admob/src/api/RewardedAdLoader.gd")
const RewardedAdLoadCallbackClass     = preload("res://addons/admob/src/api/listeners/RewardedAdLoadCallback.gd")
const OnUserEarnedRewardListenerClass = preload("res://addons/admob/src/api/listeners/OnUserEarnedRewardListener.gd")

# ===== TWOJE ID =====
const BANNER_ID       = "ca-app-pub-1542056164177824/8616200349"
const INTERSTITIAL_ID = "ca-app-pub-1542056164177824/6892055137"
const REWARDED_ID     = "ca-app-pub-1542056164177824/1063237288"

const TEST_BANNER_ID       = "ca-app-pub-3940256099942544/6300978111"
const TEST_INTERSTITIAL_ID = "ca-app-pub-3940256099942544/1033173712"
const TEST_REWARDED_ID     = "ca-app-pub-3940256099942544/5224354917"

# Zmien na false przed wyslaniem do Google Play!
const USE_TEST_ADS = true

# ===== STAN =====
var _banner_ad = null
var _interstitial_ad = null
var _rewarded_ad = null
var _is_android: bool = false
var ads_disabled: bool = false
var banner_loaded: bool = false

# ===== SYGNALY =====
signal banner_loaded_signal
signal rewarded_ad_completed
signal rewarded_ad_failed
signal interstitial_closed

func _ready():
	print("=== AdMobManager _ready ===")
	_is_android = OS.get_name() == "Android"

	if not _is_android:
		print("Nie Android - AdMob pominiete (OK w edytorze)")
		return

	var main_node = get_node_or_null("/root/Main")
	if main_node and main_node.has_method("get_ads_disabled"):
		ads_disabled = main_node.get_ads_disabled()

	if ads_disabled:
		print("Reklamy wylaczone (no-ads)")
		return

	print("Inicjalizuje MobileAds...")
	MobileAdsClass.initialize()

	await get_tree().create_timer(1.0).timeout
	_load_banner()
	_load_interstitial()
	_load_rewarded()

# ================================================================
#  BANNER
# ================================================================

func _load_banner():
	if not _is_android or ads_disabled: return

	var unit_id = TEST_BANNER_ID if USE_TEST_ADS else BANNER_ID
	print("Laduje banner: ", unit_id)

	if _banner_ad:
		_banner_ad.destroy()
		_banner_ad = null

	# AdSize.BANNER i AdPosition.Values.BOTTOM to stale statyczne - nie new()!
	_banner_ad = AdViewClass.new(unit_id, AdSizeClass.BANNER, AdPositionClass.Values.BOTTOM)

	var listener = AdListenerClass.new()
	listener.on_ad_loaded = _on_banner_loaded
	listener.on_ad_failed_to_load = _on_banner_failed
	_banner_ad.ad_listener = listener

	_banner_ad.load_ad(AdRequestClass.new())

func show_banner():
	if ads_disabled or not _is_android: return
	if _banner_ad:
		print("Pokazuje banner")
		_banner_ad.show()

func hide_banner():
	if not _is_android: return
	if _banner_ad:
		print("Ukrywam banner")
		_banner_ad.hide()

func _on_banner_loaded():
	banner_loaded = true
	print("Banner zaladowany!")
	banner_loaded_signal.emit()

func _on_banner_failed(error):
	print("Banner blad: ", error)

# ================================================================
#  INTERSTITIAL
# ================================================================

func _load_interstitial():
	if not _is_android or ads_disabled: return

	var unit_id = TEST_INTERSTITIAL_ID if USE_TEST_ADS else INTERSTITIAL_ID
	print("Laduje interstitial")

	var callback = InterstitialAdLoadCallbackClass.new()
	callback.on_ad_loaded = _on_interstitial_loaded
	callback.on_ad_failed_to_load = _on_interstitial_failed

	InterstitialAdLoaderClass.new().load(unit_id, AdRequestClass.new(), callback)

func show_interstitial():
	if ads_disabled or not _is_android: return

	if _interstitial_ad:
		print("Pokazuje interstitial")
		var cb = FullScreenContentCallbackClass.new()
		cb.on_ad_dismissed_full_screen_content = _on_interstitial_dismissed
		_interstitial_ad.full_screen_content_callback = cb
		_interstitial_ad.show()
	else:
		print("Interstitial nie gotowy - laduje...")
		_load_interstitial()

func _on_interstitial_loaded(ad):
	print("Interstitial zaladowany!")
	_interstitial_ad = ad

func _on_interstitial_failed(error):
	print("Interstitial blad: ", error)
	_interstitial_ad = null

func _on_interstitial_dismissed():
	print("Interstitial zamkniety")
	interstitial_closed.emit()
	if _interstitial_ad:
		_interstitial_ad.destroy()
		_interstitial_ad = null
	_load_interstitial()

# ================================================================
#  REWARDED
# ================================================================

func _load_rewarded():
	if not _is_android or ads_disabled: return

	var unit_id = TEST_REWARDED_ID if USE_TEST_ADS else REWARDED_ID
	print("Laduje rewarded")

	var callback = RewardedAdLoadCallbackClass.new()
	callback.on_ad_loaded = _on_rewarded_loaded
	callback.on_ad_failed_to_load = _on_rewarded_failed_load

	RewardedAdLoaderClass.new().load(unit_id, AdRequestClass.new(), callback)

func show_rewarded():
	if ads_disabled or not _is_android:
		rewarded_ad_failed.emit()
		return

	if _rewarded_ad:
		print("Pokazuje rewarded ad")
		var cb = FullScreenContentCallbackClass.new()
		cb.on_ad_dismissed_full_screen_content = _on_rewarded_dismissed
		_rewarded_ad.full_screen_content_callback = cb

		var reward_listener = OnUserEarnedRewardListenerClass.new()
		reward_listener.on_user_earned_reward = _on_user_earned_reward
		_rewarded_ad.show(reward_listener)
	else:
		print("Rewarded nie gotowy - laduje...")
		rewarded_ad_failed.emit()
		_load_rewarded()

func is_rewarded_ready() -> bool:
	if ads_disabled or not _is_android: return false
	return _rewarded_ad != null

func _on_rewarded_loaded(ad):
	print("Rewarded zaladowany!")
	_rewarded_ad = ad

func _on_rewarded_failed_load(error):
	print("Rewarded blad: ", error)
	_rewarded_ad = null
	rewarded_ad_failed.emit()

func _on_rewarded_dismissed():
	print("Rewarded zamkniety")
	if _rewarded_ad:
		_rewarded_ad.destroy()
		_rewarded_ad = null
	_load_rewarded()

func _on_user_earned_reward(reward):
	print("Nagroda zarobiona!")
	rewarded_ad_completed.emit()

# ================================================================
#  UTILITY
# ================================================================

func disable_ads():
	ads_disabled = true
	hide_banner()
	if _banner_ad:
		_banner_ad.destroy()
		_banner_ad = null
	print("Reklamy wylaczone na stale")
	var main_node = get_node_or_null("/root/Main")
	if main_node and main_node.has_method("set_ads_disabled"):
		main_node.set_ads_disabled(true)

#extends Node
## IAP Manager - Zarządzanie płatnościami in-app
## Umieść w: res://scripts/iap_manager.gd
## Dodaj jako Autoload: Project → Project Settings → Autoload
#
## ===== REFERENCJA DO PLUGINU =====
#var payment: Object = null
#var is_ready = false
#
## ===== POSIADANE PRODUKTY =====
#var owned_products: Array = []
#
## ===== SYGNAŁY =====
#signal purchase_completed(product_id: String)
#signal purchase_failed(error_message: String)
#signal purchase_cancelled
#signal products_updated
#
## ===== DEFINICJE PRODUKTÓW =====
## UWAGA: Te ID muszą się zgadzać z produktami utworzonymi w Google Play Console!
#const PRODUCTS = {
	## Non-consumable (kupujesz raz na zawsze)
	#"no_ads": {
		#"type": "non_consumable",
		#"title": "Remove Ads Forever",
		#"description": "Removes all advertisements permanently",
		#"price_display": "9.99 PLN"
	#},
	#
	## Consumable (można kupić wiele razy)
	#"time_pack_small": {
		#"type": "consumable",
		#"title": "100 Time Units",
		#"description": "Get 100 time units instantly",
		#"amount": 100,
		#"price_display": "2.99 PLN"
	#},
	#"time_pack_medium": {
		#"type": "consumable",
		#"title": "300 Time Units",
		#"description": "Get 300 time units instantly",
		#"amount": 300,
		#"price_display": "6.99 PLN",
		#"badge": "BEST VALUE"
	#},
	#"time_pack_large": {
		#"type": "consumable",
		#"title": "1000 Time Units",
		#"description": "Get 1000 time units instantly",
		#"amount": 1000,
		#"price_display": "14.99 PLN",
		#"badge": "75% BONUS"
	#}
#}
#
#func _ready():
	#print("=== IAP Manager initializing ===")
	#
	## Inicjalizuj tylko na Androidzie
	#if OS.get_name() == "Android":
		#if Engine.has_singleton("GodotGooglePlayBilling"):
			#payment = Engine.get_singleton("GodotGooglePlayBilling")
			#initialize_billing()
		#else:
			#print("⚠️ Google Play Billing plugin not found!")
			#print("   Make sure plugin is installed correctly")
	#else:
		#print("ℹ️ IAP skipped - not on Android platform")
#
#func initialize_billing():
	#"""Inicjalizuje system płatności Google Play"""
	#if not payment:
		#return
	#
	#print("Connecting to Google Play Billing...")
	#
	## Podłącz wszystkie sygnały
	#payment.connected.connect(_on_billing_connected)
	#payment.disconnected.connect(_on_billing_disconnected)
	#payment.connect_error.connect(_on_billing_connect_error)
	#payment.purchases_updated.connect(_on_purchases_updated)
	#payment.purchase_error.connect(_on_purchase_error)
	#payment.sku_details_query_completed.connect(_on_sku_details_completed)
	#payment.purchase_acknowledged.connect(_on_purchase_acknowledged)
	#payment.purchase_consumption_error.connect(_on_purchase_consumption_error)
	#payment.purchase_consumed.connect(_on_purchase_consumed)
	#
	## Rozpocznij połączenie
	#payment.startConnection()
#
## ========== CALLBACKS POŁĄCZENIA ==========
#
#func _on_billing_connected():
	#"""Połączono z Google Play Billing"""
	#print("✓ Connected to Google Play Billing")
	#is_ready = true
	#
	## Sprawdź jakie produkty użytkownik już posiada
	#query_purchases()
	#
	## Pobierz szczegóły produktów (ceny itp.)
	#query_sku_details()
#
#func _on_billing_disconnected():
	#"""Rozłączono z Google Play Billing"""
	#print("⚠️ Disconnected from Google Play Billing")
	#is_ready = false
#
#func _on_billing_connect_error(error_code: int, error_message: String):
	#"""Błąd połączenia"""
	#print("❌ Billing connection error [%d]: %s" % [error_code, error_message])
	#is_ready = false
#
## ========== QUERY PRODUKTÓW ==========
#
#func query_purchases():
	#"""Sprawdza jakie produkty użytkownik już kupił"""
	#if not is_ready or not payment:
		#return
	#
	#print("Querying owned purchases...")
	#payment.queryPurchases("inapp")
#
#func _on_purchases_updated(purchases: Array):
	#"""Otrzymano listę zakupionych produktów"""
	#print("Purchases updated: %d items" % purchases.size())
	#
	#owned_products.clear()
	#
	#for purchase in purchases:
		#var product_id = purchase.get("sku", "")
		#var purchase_token = purchase.get("purchaseToken", "")
		#var is_acknowledged = purchase.get("isAcknowledged", false)
		#
		#print("  - %s (acknowledged: %s)" % [product_id, is_acknowledged])
		#
		#owned_products.append(product_id)
		#
		## Obsłuż posiadany produkt
		#handle_owned_product(product_id)
		#
		## Jeśli nie jest acknowledged, potwierdź
		#if not is_acknowledged:
			#payment.acknowledgePurchase(purchase_token)
	#
	#products_updated.emit()
#
#func query_sku_details():
	#"""Pobiera szczegóły produktów (ceny, opisy)"""
	#if not is_ready or not payment:
		#return
	#
	#var sku_list = PRODUCTS.keys()
	#print("Querying SKU details for: %s" % sku_list)
	#payment.querySkuDetails(sku_list, "inapp")
#
#func _on_sku_details_completed(sku_details: Array):
	#"""Otrzymano szczegóły produktów z Google Play"""
	#print("SKU details received: %d products" % sku_details.size())
	#
	#for detail in sku_details:
		#var sku = detail.get("sku", "")
		#var price = detail.get("price", "")
		#var title = detail.get("title", "")
		#
		## Zaktualizuj cenę w definicji produktu
		#if PRODUCTS.has(sku):
			#PRODUCTS[sku]["price"] = price
			#print("  - %s: %s" % [sku, price])
#
## ========== ZAKUP ==========
#
#func purchase_product(product_id: String):
	#"""Rozpoczyna proces zakupu produktu"""
	#if not is_ready or not payment:
		#print("⚠️ Cannot purchase - billing not ready")
		#purchase_failed.emit("Billing system not ready")
		#return
	#
	#if not PRODUCTS.has(product_id):
		#print("⚠️ Unknown product: %s" % product_id)
		#purchase_failed.emit("Unknown product")
		#return
	#
	## Sprawdź czy już nie posiada (dla non-consumable)
	#if PRODUCTS[product_id].type == "non_consumable" and owns_product(product_id):
		#print("ℹ️ User already owns: %s" % product_id)
		#purchase_failed.emit("Already owned")
		#return
	#
	#print("🛒 Starting purchase: %s" % product_id)
	#payment.purchase(product_id)
#
#func _on_purchase_acknowledged(purchase_token: String):
	#"""Zakup został potwierdzony"""
	#print("✓ Purchase acknowledged")
#
#func _on_purchase_consumed(purchase_token: String):
	#"""Consumable został skonsumowany"""
	#print("✓ Purchase consumed")
#
#func _on_purchase_error(error_code: int, error_message: String):
	#"""Błąd podczas zakupu"""
	#if error_code == 1:  # User cancelled
		#print("🚫 Purchase cancelled by user")
		#purchase_cancelled.emit()
	#else:
		#print("❌ Purchase error [%d]: %s" % [error_code, error_message])
		#purchase_failed.emit(error_message)
#
#func _on_purchase_consumption_error(error_code: int, error_message: String):
	#"""Błąd podczas konsumpcji"""
	#print("❌ Consumption error [%d]: %s" % [error_code, error_message])
#
## ========== OBSŁUGA ZAKUPIONYCH PRODUKTÓW ==========
#
#func handle_owned_product(product_id: String):
	#"""Obsługuje posiadany produkt"""
	#if not PRODUCTS.has(product_id):
		#return
	#
	#var product = PRODUCTS[product_id]
	#
	#match product_id:
		#"no_ads":
			## Wyłącz reklamy
			#var main = get_node_or_null("/root/Main")
			#if main and main.has_method("set_ads_disabled"):
				#main.set_ads_disabled(true)
			#
			#var admob = get_node_or_null("/root/AdMobManager")
			#if admob and admob.has_method("disable_ads"):
				#admob.disable_ads()
			#
			#print("📵 No-ads activated")
#
#func handle_new_purchase(purchase: Dictionary):
	#"""Obsługuje nowo zakupiony produkt"""
	#var product_id = purchase.get("sku", "")
	#var purchase_token = purchase.get("purchaseToken", "")
	#
	#print("✅ New purchase completed: %s" % product_id)
	#
	#if not PRODUCTS.has(product_id):
		#return
	#
	#var product = PRODUCTS[product_id]
	#var main = get_node_or_null("/root/Main")
	#
	## Obsłuż według typu
	#if product.type == "non_consumable":
		## No-ads
		#if product_id == "no_ads":
			#if main and main.has_method("set_ads_disabled"):
				#main.set_ads_disabled(true)
			#
			#var admob = get_node_or_null("/root/AdMobManager")
			#if admob and admob.has_method("disable_ads"):
				#admob.disable_ads()
		#
		## Potwierdź zakup
		#payment.acknowledgePurchase(purchase_token)
		#
	#elif product.type == "consumable":
		## Paczki czasu
		#var amount = product.get("amount", 0)
		#if main and main.has_method("add_currency"):
			#main.add_currency(amount)
			#print("💰 Added %d time units" % amount)
		#
		## Skonsumuj (ważne! inaczej nie można kupić ponownie)
		#payment.consumePurchase(purchase_token)
	#
	#purchase_completed.emit(product_id)
#
## ========== UTILITY ==========
#
#func owns_product(product_id: String) -> bool:
	#"""Sprawdza czy użytkownik posiada produkt"""
	#return product_id in owned_products
#
#func get_product_info(product_id: String) -> Dictionary:
	#"""Zwraca informacje o produkcie"""
	#if PRODUCTS.has(product_id):
		#return PRODUCTS[product_id]
	#return {}
#
#func get_product_price(product_id: String) -> String:
	#"""Zwraca cenę produktu"""
	#var product = get_product_info(product_id)
	#if product.has("price"):
		#return product.price
	#elif product.has("price_display"):
		#return product.price_display
	#return ""
#
#func is_available() -> bool:
	#"""Sprawdza czy system płatności jest dostępny"""
	#return is_ready
#
## ========== RESTORE PURCHASES (iOS) ==========
## Na Androidzie restore odbywa się automatycznie przy query_purchases()
#
#func restore_purchases():
	#"""Przywraca zakupy (głównie dla iOS, ale działa też na Androidzie)"""
	#print("Restoring purchases...")
	#query_purchases()

extends Node

var payment: Object = null
var is_ready = false
var owned_products: Array = []

signal purchase_completed(product_id: String)
signal purchase_failed(error_message: String)
signal purchase_cancelled
signal products_updated

const PRODUCTS = {
	"no_ads": {
		"type": "non_consumable",
		"title": "Remove Ads Forever",
		"description": "Removes all advertisements permanently",
		"price_display": "$1.99"
	},
	"time_pack_small": {
		"type": "consumable",
		"title": "30 Time Crystals",
		"description": "Get 30 time crystals instantly",
		"amount": 30,
		"price_display": "$0.49"
	},
	"time_pack_medium": {
		"type": "consumable",
		"title": "70 Time Crystals",
		"description": "Get 70 time crystals instantly",
		"amount": 70,
		"price_display": "$0.99"
	},
	"time_pack_large": {
		"type": "consumable",
		"title": "220 Time Crystals",
		"description": "Get 220 time crystals instantly",
		"amount": 220,
		"price_display": "$2.99"
	}
}

func _ready():
	print("=== IAP Manager initializing ===")
	if OS.get_name() == "Android":
		if Engine.has_singleton("GodotGooglePlayBilling"):
			payment = Engine.get_singleton("GodotGooglePlayBilling")
			initialize_billing()
		else:
			print("WARNING: Google Play Billing plugin not found!")
	else:
		print("IAP skipped - not on Android")

func initialize_billing():
	if not payment:
		return
	print("Connecting to Google Play Billing...")
	payment.connected.connect(_on_billing_connected)
	payment.disconnected.connect(_on_billing_disconnected)
	payment.connect_error.connect(_on_billing_connect_error)
	payment.purchases_updated.connect(_on_purchases_updated)
	payment.purchase_error.connect(_on_purchase_error)
	payment.sku_details_query_completed.connect(_on_sku_details_completed)
	payment.purchase_acknowledged.connect(_on_purchase_acknowledged)
	payment.purchase_consumption_error.connect(_on_purchase_consumption_error)
	payment.purchase_consumed.connect(_on_purchase_consumed)
	payment.startConnection()

func _on_billing_connected():
	print("Connected to Google Play Billing")
	is_ready = true
	query_purchases()
	query_sku_details()

func _on_billing_disconnected():
	print("Disconnected from Google Play Billing")
	is_ready = false

func _on_billing_connect_error(error_code: int, error_message: String):
	print("Billing connection error [%d]: %s" % [error_code, error_message])
	is_ready = false

func query_purchases():
	if not is_ready or not payment:
		return
	print("Querying owned purchases...")
	payment.queryPurchases("inapp")

func _on_purchases_updated(purchases: Array):
	print("Purchases updated: %d items" % purchases.size())
	owned_products.clear()
	for purchase in purchases:
		var product_id = purchase.get("sku", "")
		var purchase_token = purchase.get("purchaseToken", "")
		var is_acknowledged = purchase.get("isAcknowledged", false)
		print("  - %s (acknowledged: %s)" % [product_id, is_acknowledged])
		owned_products.append(product_id)
		handle_owned_product(product_id)
		if not is_acknowledged:
			payment.acknowledgePurchase(purchase_token)
	products_updated.emit()

func query_sku_details():
	if not is_ready or not payment:
		return
	var sku_list = PRODUCTS.keys()
	print("Querying SKU details for: %s" % sku_list)
	payment.querySkuDetails(sku_list, "inapp")

func _on_sku_details_completed(sku_details: Array):
	print("SKU details received: %d products" % sku_details.size())
	for detail in sku_details:
		var sku = detail.get("sku", "")
		var price = detail.get("price", "")
		if PRODUCTS.has(sku):
			PRODUCTS[sku]["price"] = price
			print("  - %s: %s" % [sku, price])

func purchase_product(product_id: String):
	if not is_ready or not payment:
		print("Cannot purchase - billing not ready")
		purchase_failed.emit("Billing system not ready")
		return
	if not PRODUCTS.has(product_id):
		print("Unknown product: %s" % product_id)
		purchase_failed.emit("Unknown product")
		return
	if PRODUCTS[product_id].type == "non_consumable" and owns_product(product_id):
		print("User already owns: %s" % product_id)
		purchase_failed.emit("Already owned")
		return
	print("Starting purchase: %s" % product_id)
	payment.purchase(product_id)

func _on_purchase_acknowledged(purchase_token: String):
	print("Purchase acknowledged")

func _on_purchase_consumed(purchase_token: String):
	print("Purchase consumed")

func _on_purchase_error(error_code: int, error_message: String):
	if error_code == 1:
		print("Purchase cancelled by user")
		purchase_cancelled.emit()
	else:
		print("Purchase error [%d]: %s" % [error_code, error_message])
		purchase_failed.emit(error_message)

func _on_purchase_consumption_error(error_code: int, error_message: String):
	print("Consumption error [%d]: %s" % [error_code, error_message])

func handle_owned_product(product_id: String):
	if not PRODUCTS.has(product_id):
		return
	match product_id:
		"no_ads":
			var main = get_node_or_null("/root/Main")
			if main and main.has_method("set_ads_disabled"):
				main.set_ads_disabled(true)
			var admob = get_node_or_null("/root/AdMobManager")
			if admob and admob.has_method("disable_ads"):
				admob.disable_ads()
			print("No-ads activated")

func handle_new_purchase(purchase: Dictionary):
	var product_id = purchase.get("sku", "")
	var purchase_token = purchase.get("purchaseToken", "")
	print("New purchase completed: %s" % product_id)
	if not PRODUCTS.has(product_id):
		return
	var product = PRODUCTS[product_id]
	var main = get_node_or_null("/root/Main")
	if product.type == "non_consumable":
		if product_id == "no_ads":
			if main and main.has_method("set_ads_disabled"):
				main.set_ads_disabled(true)
			var admob = get_node_or_null("/root/AdMobManager")
			if admob and admob.has_method("disable_ads"):
				admob.disable_ads()
		payment.acknowledgePurchase(purchase_token)
	elif product.type == "consumable":
		var amount = product.get("amount", 0)
		if main and main.has_method("add_currency"):
			main.add_currency(amount)
			print("Added %d time crystals" % amount)
		payment.consumePurchase(purchase_token)
	purchase_completed.emit(product_id)

func restore_purchases():
	print("Restoring purchases...")
	query_purchases()

func owns_product(product_id: String) -> bool:
	return product_id in owned_products

func get_product_info(product_id: String) -> Dictionary:
	if PRODUCTS.has(product_id):
		return PRODUCTS[product_id]
	return {}

func get_product_price(product_id: String) -> String:
	var product = get_product_info(product_id)
	if product.has("price"):
		return product.price
	elif product.has("price_display"):
		return product.price_display
	return ""

func is_available() -> bool:
	return is_ready

extends Node

var billing_client = null
var is_ready = false
var owned_products: Array = []

signal purchase_completed(product_id: String)
signal purchase_failed(error_message: String)
signal purchase_cancelled
signal products_updated
signal restore_completed(restored_count: int)

const PRODUCTS = {
	"no_ads": {
		"type": "non_consumable",
		"title": "Remove Ads Forever",
		"description": "Removes all advertisements permanently",
		"price_display": "$1.99"
	},
	"time_pack_small": {
		"type": "consumable",
		"title": "30 Chrono Relics",
		"description": "Instantly receive 30 Chrono Relics",
		"amount": 30,
		"price_display": "$0.49"
	},
	"time_pack_medium": {
		"type": "consumable",
		"title": "70 Chrono Relics",
		"description": "Instantly receive 70 Chrono Relics",
		"amount": 70,
		"price_display": "$0.99"
	},
	"time_pack_large": {
		"type": "consumable",
		"title": "220 Chrono Relics",
		"description": "Instantly receive 220 Chrono Relics",
		"amount": 220,
		"price_display": "$2.99"
	},
	"time_pack_mega": {
		"type": "consumable",
		"title": "Mega Bundle — 420 Chrono Relics",
		"description": "Instantly receive 420 Chrono Relics",
		"amount": 420,
		"price_display": "$4.99"
	}
}

func _ready():
	print("=== IAP Manager initializing ===")
	if OS.get_name() == "Android":
		billing_client = BillingClient.new()
		billing_client.connected.connect(_on_billing_connected)
		billing_client.disconnected.connect(_on_billing_disconnected)
		billing_client.connect_error.connect(_on_billing_connect_error)
		billing_client.on_purchases_updated.connect(_on_purchases_updated)
		billing_client.query_purchases_response.connect(_on_query_purchases)
		billing_client.product_details_query_completed.connect(_on_product_details_completed)
		billing_client.purchase_acknowledged.connect(_on_purchase_acknowledged)
		billing_client.purchase_consumed.connect(_on_purchase_consumed)
		billing_client.start_connection()
		print("Connecting to Google Play Billing...")
	else:
		print("IAP skipped - not on Android")

func _on_billing_connected():
	print("Connected to Google Play Billing!")
	is_ready = true
	query_product_details()
	query_purchases()

func _on_billing_disconnected():
	print("Disconnected from Google Play Billing")
	is_ready = false

func _on_billing_connect_error(error_code: int, error_message: String):
	print("Billing connection error [%d]: %s" % [error_code, error_message])
	is_ready = false

func query_purchases():
	if not is_ready or not billing_client:
		return
	print("Querying owned purchases...")
	billing_client.query_purchases(BillingClient.ProductType.INAPP)

func query_product_details():
	if not is_ready or not billing_client:
		return
	var product_list = PRODUCTS.keys()
	print("Querying product details for: %s" % product_list)
	billing_client.query_product_details(product_list, BillingClient.ProductType.INAPP)

func _on_query_purchases(result: Dictionary):
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		print("Query purchases failed: ", result.get("debug_message", ""))
		return
	var purchases = result.get("purchases", [])
	print("Query purchases: %d items" % purchases.size())
	owned_products.clear()
	for purchase in purchases:
		var product_id = purchase.get("product_ids", [""])[0]
		var purchase_token = purchase.get("purchase_token", "")
		var is_acknowledged = purchase.get("is_acknowledged", false)
		owned_products.append(product_id)
		handle_owned_product(product_id)
		if not is_acknowledged:
			billing_client.acknowledge_purchase(purchase_token)
	products_updated.emit()
	restore_completed.emit(purchases.size())

func _on_purchases_updated(result: Dictionary):
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		var response_code = result.get("response_code", -1)
		# 1 = user cancelled
		if response_code == 1:
			purchase_cancelled.emit()
		else:
			print("Purchase error: ", result.get("debug_message", ""))
			purchase_failed.emit(result.get("debug_message", "Unknown error"))
		return
	var purchases = result.get("purchases", [])
	for purchase in purchases:
		handle_new_purchase(purchase)

func _on_product_details_completed(result: Dictionary):
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		print("Product details failed: ", result.get("debug_message", ""))
		return
	var product_details = result.get("product_details", [])
	print("Product details received: %d" % product_details.size())
	for detail in product_details:
		var sku = detail.get("product_id", "")
		var price = detail.get("price", "")
		if PRODUCTS.has(sku):
			PRODUCTS[sku]["price"] = price
			print("  - %s: %s" % [sku, price])

func purchase_product(product_id: String):
	if not is_ready or not billing_client:
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
	billing_client.purchase(product_id)

func _on_purchase_acknowledged(purchase_token: String):
	print("Purchase acknowledged: %s" % purchase_token)

func _on_purchase_consumed(purchase_token: String):
	print("Purchase consumed: %s" % purchase_token)

func handle_new_purchase(purchase: Dictionary):
	var product_id = purchase.get("product_ids", [""])[0]
	var purchase_token = purchase.get("purchase_token", "")
	var purchase_state = purchase.get("purchase_state", 0)
	print("New purchase: %s state: %d" % [product_id, purchase_state])

	# 1 = PURCHASED
	if purchase_state != 1:
		return

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
		billing_client.acknowledge_purchase(purchase_token)
	elif product.type == "consumable":
		var amount = product.get("amount", 0)
		if main and main.has_method("add_currency"):
			main.add_currency(amount)
			print("Added %d Chrono Relics" % amount)
		billing_client.consume_purchase(purchase_token)

	purchase_completed.emit(product_id)

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

func restore_purchases():
	print("Restoring purchases...")
	query_purchases()

func owns_product(product_id: String) -> bool:
	return product_id in owned_products

func get_product_price(product_id: String) -> String:
	var product = PRODUCTS.get(product_id, {})
	if product.has("price"):
		return product.price
	elif product.has("price_display"):
		return product.price_display
	return ""

func is_available() -> bool:
	return is_ready

extends Node

# =====================================================
# ConsentManager - GDPR / UMP dla Hex Wars
# Dodaj jako Autoload: Project Settings → Autoload
# Nazwa: ConsentManager
# =====================================================
# KOLEJNOŚĆ AUTOLOAD powinna być:
#   1. Main
#   2. AdMobManager
#   3. ConsentManager  ← on odpala reklamy po zgodzie
# =====================================================

var _consent_form: ConsentForm

func _ready():
	# Odczekaj chwilę żeby AdMobManager zdążył się zainicjalizować
	await get_tree().process_frame
	await get_tree().process_frame
	request_consent()

func request_consent():
	if OS.get_name() != "Android":
		print("ConsentManager: nie Android, pomijam UMP")
		_start_ads()
		return

	var request := ConsentRequestParameters.new()

	# ⚠️ TYLKO DO TESTÓW - symuluje użytkownika z EU
	# Odkomentuj podczas testowania, zakomentuj przed wydaniem!
	# var debug := ConsentDebugSettings.new()
	# debug.debug_geography = DebugGeography.Values.EEA
	# request.consent_debug_settings = debug

	UserMessagingPlatform.consent_information.update(
		request,
		_on_consent_info_updated,
		_on_consent_error
	)

func _on_consent_info_updated():
	var status = UserMessagingPlatform.consent_information.get_consent_status()
	print("ConsentManager: status = ", status)

	# Sprawdź czy formularz jest w ogóle potrzebny
	if not UserMessagingPlatform.consent_information.is_consent_form_available():
		print("ConsentManager: formularz niedostępny, startuj reklamy")
		_start_ads()
		return

	# Jeśli zgoda już była udzielona wcześniej - nie pokazuj ponownie
	if status == UserMessagingPlatform.consent_information.ConsentStatus.OBTAINED:
		print("ConsentManager: zgoda już była, startuj reklamy")
		_start_ads()
		return

	# Załaduj i pokaż formularz
	UserMessagingPlatform.load_consent_form(
		_on_form_loaded,
		_on_consent_error
	)

func _on_form_loaded(form: ConsentForm):
	_consent_form = form
	var status = UserMessagingPlatform.consent_information.get_consent_status()

	if status == UserMessagingPlatform.consent_information.ConsentStatus.REQUIRED:
		# Pokaż dialog zgody użytkownikowi
		form.show(_on_form_dismissed)
	else:
		# Nie wymagana (użytkownik spoza EU) - od razu reklamy
		_start_ads()

func _on_form_dismissed(_error: FormError):
	# Po zamknięciu formularza zawsze startuj reklamy
	# AdMob sam dostosuje typ (spersonalizowane / niespersonalizowane)
	print("ConsentManager: formularz zamknięty, startuj reklamy")
	_start_ads()

func _on_consent_error(error: FormError):
	# Błąd UMP - i tak pokaż reklamy (niespersonalizowane)
	print("ConsentManager: błąd UMP: ", error.get_message())
	_start_ads()

func _start_ads():
	var admob = get_node_or_null("/root/AdMobManager")
	if not admob:
		print("ConsentManager: brak AdMobManager")
		return

	var main = get_node_or_null("/root/Main")
	if main and main.has_method("get_ads_disabled") and main.get_ads_disabled():
		print("ConsentManager: reklamy wyłączone (no_ads zakupione)")
		return

	print("ConsentManager: pokazuję banner")
	if admob.has_method("show_banner"):
		admob.show_banner()

# Wywołaj to żeby pokazać użytkownikowi opcje zgody ponownie
# (np. przycisk "Ustawienia prywatności" w menu)
func show_privacy_options():
	if _consent_form:
		_consent_form.show(_on_form_dismissed)
	else:
		print("ConsentManager: brak formularza do pokazania")

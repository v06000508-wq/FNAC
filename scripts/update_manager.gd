extends Node

# Версия игры для ПК (для Android версия определяется автоматически через JNI)
const DEFAULT_VERSION_CODE: int = 1
const VERSION_JSON_URL: String = "https://raw.githubusercontent.com/v06000508-wq/FNAC/main/version.json"

@onready var http_request: HTTPRequest = HTTPRequest.new()
var apk_download_url: String = ""
var local_apk_path: String = ""
var is_checking_manually: bool = false

# UI элементы оверлея
var update_overlay: Panel = null
var progress_bar: ProgressBar = null
var status_label: Label = null
var download_btn: Button = null
var cancel_btn: Button = null

# Сигналы для интеграции
signal update_available(changelog: String, version_name: String)
signal download_progress(percentage: float)
signal download_completed()
signal download_failed()

func _ready() -> void:
	# На Android сохраняем в кеш, так как он доступен для FileProvider
	if OS.get_name() == "Android":
		local_apk_path = OS.get_cache_dir() + "/update.apk"
	else:
		local_apk_path = "user://update.apk"
		
	# Добавляем узел сетевого запроса
	add_child(http_request)
	http_request.request_completed.connect(_on_version_check_completed)
	
	# Ждем один кадр перед автоматической проверкой на старте
	await get_tree().process_frame
	check_for_updates(false)

# Проверка обновлений (force_manual = true показывает окно ожидания проверки)
func check_for_updates(force_manual: bool = false) -> void:
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
		
	is_checking_manually = force_manual
	
	if is_checking_manually:
		_show_status_popup("Проверка обновлений...")
		
	var err = http_request.request(VERSION_JSON_URL)
	if err != OK:
		print("[UpdateManager] Ошибка отправки запроса: ", err)
		if is_checking_manually:
			_show_status_popup("Ошибка сети при проверке!", true)

# Обработка ответа о версии
func _on_version_check_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		print("[UpdateManager] Сервер обновлений вернул ошибку: ", response_code)
		if is_checking_manually:
			_show_status_popup("Сервер обновлений недоступен!", true)
		return
		
	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		print("[UpdateManager] Ошибка парсинга JSON")
		if is_checking_manually:
			_show_status_popup("Ошибка чтения данных сервера!", true)
		return
		
	var data = json.get_data()
	var server_version_code = int(data.get("version_code", 0))
	var server_version_name = str(data.get("version_name", "1.0.0"))
	var changelog = str(data.get("changelog", ""))
	apk_download_url = str(data.get("apk_url", ""))
	
	# Закрываем окно ожидания, если оно было
	_close_status_popup()
	
	var local_version_code = get_local_version_code()
	if server_version_code > local_version_code:
		print("[UpdateManager] Доступно обновление: ", server_version_name)
		update_available.emit(changelog, server_version_name)
		_show_update_modal(server_version_name, changelog)
	else:
		print("[UpdateManager] У вас установлена последняя версия.")
		if is_checking_manually:
			_show_status_popup("У вас последняя версия!", true)

# Показ статусного окна (для ручной проверки)
var status_popup: Panel = null
func _show_status_popup(text: String, show_close: bool = false) -> void:
	_close_status_popup()
	
	var root = get_tree().root
	if not root: return
	
	status_popup = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.95)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(1.0, 0.2, 0.2, 0.8)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	status_popup.add_theme_stylebox_override("panel", sb)
	
	status_popup.set_anchors_preset(Control.PRESET_CENTER)
	status_popup.size = Vector2(400, 160)
	status_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	status_popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(status_popup)
	
	var container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 15)
	status_popup.add_child(container)
	
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Courier New", "Consolas", "Monospace"])
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.9))
	container.add_child(lbl)
	
	if show_close:
		var btn = Button.new()
		btn.text = "[ ЗАКРЫТЬ ]"
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_close_status_popup)
		container.add_child(btn)

func _close_status_popup() -> void:
	if status_popup and is_instance_valid(status_popup):
		status_popup.queue_free()
	status_popup = null

# Создание кастомного FNAF-стилизованного диалогового окна обновления
func _show_update_modal(version_name: String, changelog: String) -> void:
	if update_overlay and is_instance_valid(update_overlay):
		return
		
	var root = get_tree().root
	if not root: return
	
	update_overlay = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.97)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(1.0, 0.15, 0.15, 0.95) # Ярко-красный бордер
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	update_overlay.add_theme_stylebox_override("panel", sb)
	
	update_overlay.set_anchors_preset(Control.PRESET_CENTER)
	update_overlay.size = Vector2(600, 340)
	update_overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	update_overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(update_overlay)
	
	var container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.offset_left = 25
	container.offset_top = 20
	container.offset_right = -25
	container.offset_bottom = -20
	container.add_theme_constant_override("separation", 14)
	update_overlay.add_child(container)
	
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Courier New", "Consolas", "Monospace"])
	
	# Заголовок
	var title = Label.new()
	title.text = "[ ДОСТУПНО ОБНОВЛЕНИЕ v%s ]" % version_name
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)
	
	# Подзаголовок изменений
	var change_lbl = Label.new()
	change_lbl.text = "Список изменений:"
	change_lbl.add_theme_font_override("font", font)
	change_lbl.add_theme_font_size_override("font_size", 14)
	change_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	container.add_child(change_lbl)
	
	# Текст лога изменений с прокруткой
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)
	
	var log_text = Label.new()
	log_text.text = changelog if not changelog.is_empty() else "- Мелкие улучшения и исправления стабильности."
	log_text.add_theme_font_override("font", font)
	log_text.add_theme_font_size_override("font_size", 13)
	log_text.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	log_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	log_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(log_text)
	
	# Строка статуса и прогресс бар
	status_label = Label.new()
	status_label.text = "Новая версия готова к установке."
	status_label.add_theme_font_override("font", font)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(status_label)
	
	progress_bar = ProgressBar.new()
	progress_bar.visible = false
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = true
	container.add_child(progress_bar)
	
	# Ряд кнопок
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 50)
	container.add_child(btn_row)
	
	download_btn = Button.new()
	download_btn.text = "[ УСТАНОВИТЬ ОБНОВЛЕНИЕ ]"
	download_btn.add_theme_font_override("font", font)
	download_btn.add_theme_font_size_override("font_size", 16)
	download_btn.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	download_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	download_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	download_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	download_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	download_btn.pressed.connect(_on_download_pressed)
	btn_row.add_child(download_btn)
	
	cancel_btn = Button.new()
	cancel_btn.text = "[ ОТМЕНА ]"
	cancel_btn.add_theme_font_override("font", font)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	cancel_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	cancel_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	cancel_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	cancel_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(cancel_btn)

func _on_download_pressed() -> void:
	# Сразу открываем прямую ссылку на скачивание APK в системном мобильном браузере
	# Смартфон сам скачает и предложит обновить игру напрямую
	OS.shell_open(apk_download_url)
	
	# Закрываем оверлей обновления
	if update_overlay and is_instance_valid(update_overlay):
		update_overlay.queue_free()
	update_overlay = null

func _on_cancel_pressed() -> void:
	if update_overlay and is_instance_valid(update_overlay):
		update_overlay.queue_free()
	update_overlay = null

# Процесс скачивания APK
func start_downloading_apk() -> void:
	if apk_download_url.is_empty():
		status_label.text = "Ошибка: URL файла пуст!"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		return
		
	var downloader = HTTPRequest.new()
	add_child(downloader)
	downloader.download_file = local_apk_path
	
	var timer = Timer.new()
	timer.wait_time = 0.1
	add_child(timer)
	timer.timeout.connect(func():
		if is_instance_valid(downloader):
			var body_size = downloader.get_body_size()
			var downloaded = downloader.get_downloaded_bytes()
			if body_size > 0:
				var percent = float(downloaded) / float(body_size) * 100.0
				progress_bar.value = percent
				status_label.text = "Скачивание обновления: %.1f%%" % percent
				download_progress.emit(percent)
	)
	timer.start()
	
	downloader.request_completed.connect(func(res, code, hdrs, bdy):
		timer.queue_free()
		downloader.queue_free()
		if code == 200:
			status_label.text = "Скачивание завершено! Запуск установщика..."
			status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
			download_completed.emit()
			# Задержка перед запуском установки
			await get_tree().create_timer(1.0).timeout
			install_apk()
		else:
			status_label.text = "Ошибка скачивания обновления (Код: %d)!" % code
			status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
			download_failed.emit()
			
			# Возвращаем кнопки
			download_btn.visible = true
			cancel_btn.visible = true
			progress_bar.visible = false
	)
	
	var err = downloader.request(apk_download_url)
	if err != OK:
		status_label.text = "Ошибка создания сетевого подключения!"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))

# Системная установка APK через Android Intent (JNI)
func install_apk() -> void:
	if OS.get_name() != "Android":
		status_label.text = "Установка доступна только на Android!"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		print("Установка APK доступна только на реальном Android устройстве!")
		return
		
	var absolute_path = ProjectSettings.globalize_path(local_apk_path)
	
	# Проверка существования файла перед вызовом JNI
	var file = FileAccess.open(local_apk_path, FileAccess.READ)
	if not file:
		status_label.text = "Файл APK не найден!"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		# Запускаем резервный способ
		await get_tree().create_timer(1.5).timeout
		_run_fallback_web_install()
		return
	file.close()

	print("[UpdateManager] Запуск JNI-установщика APK из пути: ", absolute_path)
	
	var jni_success = false
	
	# Безопасный вызов JNI с проверкой синглтона GodotAndroid
	if Engine.has_singleton("GodotAndroid"):
		var godot_android = Engine.get_singleton("GodotAndroid")
		if godot_android:
			var activity = godot_android.get_activity()
			if activity:
				var context = activity.getApplicationContext()
				if context:
					var intent_class = JavaClassWrapper.wrap("android.content.Intent")
					var file_class = JavaClassWrapper.wrap("java.io.File")
					var file_provider_class = JavaClassWrapper.wrap("androidx.core.content.FileProvider")
					
					if intent_class and file_class and file_provider_class:
						var apk_file = file_class.new(absolute_path)
						
						# В Godot 4 стандартный FileProvider имеет суффикс .fileprovider
						var provider_authority = context.getPackageName() + ".fileprovider"
						print("[UpdateManager] Используем FileProvider authority: ", provider_authority)
						
						var apk_uri = file_provider_class.getUriForFile(context, provider_authority, apk_file)
						if apk_uri:
							# Создаем Intent для просмотра/установки
							var install_intent = intent_class.new(intent_class.ACTION_VIEW)
							install_intent.setDataAndType(apk_uri, "application/vnd.android.package-archive")
							install_intent.addFlags(intent_class.FLAG_GRANT_READ_URI_PERMISSION)
							install_intent.addFlags(intent_class.FLAG_ACTIVITY_NEW_TASK)
							
							# Запуск системного окна установки
							activity.startActivity(install_intent)
							jni_success = true
							print("[UpdateManager] Системный установщик JNI успешно запущен!")
							
							# Закрываем оверлей после запуска установщика
							if update_overlay and is_instance_valid(update_overlay):
								update_overlay.queue_free()
							update_overlay = null
	
	if not jni_success:
		print("[UpdateManager] JNI-установка не удалась или не поддерживается. Переход на резервный веб-метод...")
		_run_fallback_web_install()

# Резервный метод установки через системный браузер (работает всегда)
func _run_fallback_web_install() -> void:
	status_label.text = "Запуск установщика в браузере..."
	status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	
	# Небольшая задержка, чтобы пользователь успел прочитать статус
	await get_tree().create_timer(1.5).timeout
	
	# Открываем прямую ссылку на скачивание APK в мобильном браузере
	# Смартфон сам скачает и предложит обновить игру
	OS.shell_open(apk_download_url)
	
	if update_overlay and is_instance_valid(update_overlay):
		update_overlay.queue_free()
	update_overlay = null

# Получение текущего кода версии приложения (для Android через JNI, для ПК из DEFAULT_VERSION_CODE)
func get_local_version_code() -> int:
	var code = DEFAULT_VERSION_CODE
	if OS.get_name() == "Android":
		if Engine.has_singleton("GodotAndroid"):
			var godot_android = Engine.get_singleton("GodotAndroid")
			if godot_android:
				var activity = godot_android.get_activity()
				if activity:
					var context = activity.getApplicationContext()
					if context:
						var manager = context.getPackageManager()
						if manager:
							var info = manager.getPackageInfo(context.getPackageName(), 0)
							if info:
								code = info.versionCode
								print("[UpdateManager] Получен код версии из Android: ", code)
	return code

# Получение текущего названия версии приложения (для Android через JNI)
func get_local_version_name() -> String:
	var vname = "1.0.0"
	if OS.get_name() == "Android":
		if Engine.has_singleton("GodotAndroid"):
			var godot_android = Engine.get_singleton("GodotAndroid")
			if godot_android:
				var activity = godot_android.get_activity()
				if activity:
					var context = activity.getApplicationContext()
					if context:
						var manager = context.getPackageManager()
						if manager:
							var info = manager.getPackageInfo(context.getPackageName(), 0)
							if info:
								vname = info.versionName
								print("[UpdateManager] Получено название версии из Android: ", vname)
	return vname

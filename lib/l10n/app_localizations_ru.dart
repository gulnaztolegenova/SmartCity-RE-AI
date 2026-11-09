// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get accountSection => 'Данные аккаунта';

  @override
  String get accountUid => 'ID пользователя';

  @override
  String get activeSite => 'Активный объект';

  @override
  String get addSite => 'Добавить объект';

  @override
  String get address => 'Адрес';

  @override
  String get appTagline =>
      'Платформа прогнозирования возобновляемой энергии и оптимизации нагрузки для Smart City';

  @override
  String get appTitle => 'Smart City Renewable AI';

  @override
  String get authBack => 'Назад';

  @override
  String get authAutoVerifyHint =>
      'После полного ввода кода подтверждение начнётся автоматически.';

  @override
  String get authBenefitForecast =>
      'Профессиональные прогнозы солнечной и ветровой генерации на 7 и 14 дней';

  @override
  String get authBenefitMap =>
      'Управление объектами на карте и адаптация параметров под каждую локацию';

  @override
  String get authBenefitOptimization =>
      'Панели оптимизации нагрузки, батареи и энергетического баланса';

  @override
  String get authChangePhone => 'Изменить номер';

  @override
  String get authCodeSentBadge => 'Код отправлен';

  @override
  String get authCodeHint => 'Введите 6-значный код из SMS';

  @override
  String get authCodeLabel => 'Код подтверждения';

  @override
  String get authErrorSendCode =>
      'Не удалось отправить код. Повторите попытку.';

  @override
  String get authErrorVerify => 'Проверка кода не удалась.';

  @override
  String get authHeroSubtitle =>
      'Единая цифровая среда для управления солнечной и ветровой энергетикой с фокусом на условия г. Астаны.';

  @override
  String get authHeroTitle =>
      'Пользовательский кабинет для точного управления возобновляемой энергией';

  @override
  String get authInvalidPhone => 'Введите корректный номер телефона.';

  @override
  String authOtpSubtitle(Object phone) {
    return 'Введите код подтверждения, отправленный на номер $phone.';
  }

  @override
  String get authOtpTitle => 'Подтверждение входа';

  @override
  String get authOtpSent => 'Код отправлен. Продолжите вход.';

  @override
  String get authPhoneEntryDescription =>
      'Введите номер телефона, чтобы войти в личный кабинет.';

  @override
  String get authPhoneHint => '700 000 00 00';

  @override
  String get authPhoneLabel => 'Номер телефона';

  @override
  String get authSendCode => 'Отправить код';

  @override
  String get authSmsHelper => '';

  @override
  String get authSubtitle =>
      'Войдите по номеру телефона. При первом входе заполняется только основной профиль, а параметры объекта добавляются позже на карте.';

  @override
  String get authTitle => 'Вход в личный кабинет';

  @override
  String get authVerifyingCode => 'Код проверяется';

  @override
  String get authVerify => 'Подтвердить вход';

  @override
  String get averageRisk => 'Оценка модели, не вероятность аварии';

  @override
  String get azimuth => 'Азимут';

  @override
  String get backupEmail => 'Резервный e-mail';

  @override
  String get backToForecast => 'Назад к прогнозу';

  @override
  String get batteryCapacity => 'Ёмкость батареи';

  @override
  String get batteryEnabled => 'Включить сценарий батареи';

  @override
  String get batteryScenario => 'Сценарий батареи';

  @override
  String get batterySoc => 'Заряд батареи';

  @override
  String get batterySocSubtitle => 'Профиль SOC во времени';

  @override
  String get cancel => 'Отмена';

  @override
  String get chargePower => 'Мощность заряда';

  @override
  String get city => 'Город';

  @override
  String get completeRegistration => 'Завершить регистрацию';

  @override
  String get connectedServer => 'Подключённый сервер';

  @override
  String get currentTemperature => 'Температура';

  @override
  String get dailyBreakdown => 'Суточная структура';

  @override
  String get dailyBreakdownSubtitle =>
      'Дневное распределение солнечной и ветровой генерации';

  @override
  String get dashboardHeroSubtitle =>
      'Эта панель собирает в одном месте краткий прогноз объекта, климатические условия и состояние энергетической системы.';

  @override
  String get dashboardHeroTitle => 'Краткий обзор энергетической ситуации';

  @override
  String get dashboardSiteControlSubtitle =>
      'Выберите установленную точку, которая должна определять состояние панели.';

  @override
  String get dashboardInstalledPoints => 'Установленные точки';

  @override
  String get dashboardDefaultSiteSaved => 'Основной объект обновлён.';

  @override
  String get dashboardDefaultSiteSaveError =>
      'Не удалось обновить основной объект.';

  @override
  String get dashboardOperationalFocusTitle => 'Операционный фокус';

  @override
  String get dashboardOperationalFocusSubtitle =>
      'Компактная экспертная сводка на основе прогноза, климата и энергетического баланса.';

  @override
  String get dashboardRecommendedAction => 'Рекомендуемое действие';

  @override
  String get dashboardPeakWindow => 'Пиковое окно';

  @override
  String get dashboardCoverageMode => 'Режим покрытия';

  @override
  String get dashboardStableMode => 'Стабильное окно ВИЭ';

  @override
  String get dashboardSolarMode => 'Преимущественно солнечный интервал';

  @override
  String get dashboardWindMode => 'Интервал с поддержкой ветра';

  @override
  String get dashboardGridMode => 'Требуется поддержка сети';

  @override
  String get dashboardStableAction =>
      'Сместите гибкую нагрузку к периоду пика ВИЭ и сохраните запас батареи на вечерние часы.';

  @override
  String get dashboardSolarAction =>
      'Используйте дневное окно генерации для энергоёмких задач и снижайте импорт из сети до заката.';

  @override
  String get dashboardWindAction =>
      'Удерживайте баланс между ветровой генерацией и накопителем, чтобы сгладить краткосрочную изменчивость.';

  @override
  String get dashboardGridAction =>
      'Приоритизируйте критические нагрузки и сохраняйте резерв батареи до улучшения генерации.';

  @override
  String get dashboardGridDependency => 'Зависимость от сети';

  @override
  String get dashboardGridDependencyHint =>
      'Доля спроса, которая сейчас покрывается внешним импортом из сети';

  @override
  String get day => 'День';

  @override
  String get day14 => '14 дней';

  @override
  String get day7 => '7 дней';

  @override
  String get defaultSite => 'Основной объект';

  @override
  String get delete => 'Удалить';

  @override
  String get deleteSiteConfirm =>
      'Вы действительно хотите удалить этот объект?';

  @override
  String get dischargePower => 'Мощность разряда';

  @override
  String get edit => 'Редактировать';

  @override
  String get energyMix => 'Структура генерации';

  @override
  String get extremeRisk => 'Индекс высокой генерации';

  @override
  String get fetchErrorGeneric =>
      'Произошла ошибка при загрузке данных с сервера.';

  @override
  String get forecast14Day => 'Прогноз на 14 дней';

  @override
  String get forecast7Day => 'Прогноз на 7 дней';

  @override
  String get forecastDayDetailTitle => 'Профиль выбранного дня';

  @override
  String get forecastDayDetailSubtitle =>
      'Детальный внутридневной профиль генерации с шагом 15 минут.';

  @override
  String get forecastDayUnavailable =>
      'Выбранный день недоступен в активном диапазоне прогноза.';

  @override
  String get forecastDetailInsightTitle => 'Анализ выбранной точки';

  @override
  String get forecastDetailInsightSubtitle =>
      'Операционная интерпретация зафиксированной точки на дневном графике.';

  @override
  String get forecastOpenDay => 'Открыть день подробно';

  @override
  String get forecastOpenDaySubtitle =>
      'Нажмите на день в графике или таблице, чтобы открыть полный внутридневной профиль.';

  @override
  String get forecastPageTitle => 'Подробный прогноз генерации';

  @override
  String get forecastPointRecommendation => 'Рекомендуемое действие';

  @override
  String get forecastPointRisk => 'Индекс в этот час';

  @override
  String get forecastPointTime => 'Время';

  @override
  String get forecastRecommendationRisk =>
      'Модель указывает на высокую генерацию. Сопоставьте прогноз с нагрузкой и доступной ёмкостью батареи.';

  @override
  String get forecastRecommendationSolar =>
      'Используйте сильный солнечный интервал для гибких дневных процессов и зарядки батареи.';

  @override
  String get forecastRecommendationStable =>
      'Профиль ВИЭ сбалансирован. Сохраняйте стандартный режим и контролируйте следующее окно перехода.';

  @override
  String get forecastRecommendationWind =>
      'Поддержка ветра повышена. Сглаживайте профиль накопителем и избегайте резких скачков нагрузки.';

  @override
  String get forecastTable => 'Суточная таблица';

  @override
  String get forecastTableSubtitle => 'Сводные значения и доли по дням';

  @override
  String get forecastTapDayHint =>
      'Выбор дня открывает детальную страницу профиля.';

  @override
  String get fullName => 'ФИО';

  @override
  String get goToSites => 'Перейти к объектам';

  @override
  String get gridImportAfter => 'Импорт из сети после';

  @override
  String get gridImportBefore => 'Импорт из сети до';

  @override
  String get healthStatus => 'Состояние сервиса';

  @override
  String get hourlyCurve => 'Почасовая кривая';

  @override
  String get hourlyCurveSubtitle =>
      'Солнечная, ветровая и суммарная генерация на ближайшие 72 часа';

  @override
  String get humidity => 'Влажность';

  @override
  String get initialCharge => 'Начальный заряд';

  @override
  String get initialSiteNameDefault => 'Основной объект Астаны';

  @override
  String get invalidEmail => 'Некорректный формат e-mail.';

  @override
  String get invalidNumber => 'Введите числовое значение.';

  @override
  String get language => 'Язык';

  @override
  String get languageEnglish => 'Английский';

  @override
  String get languageKazakh => 'Казахский';

  @override
  String get languageRussian => 'Русский';

  @override
  String get languageShortEnglish => 'ENG';

  @override
  String get languageShortKazakh => 'ҚАЗ';

  @override
  String get languageShortRussian => 'РУС';

  @override
  String get latitude => 'Широта';

  @override
  String get lastUpdatedLabel => 'Дата последнего обновления';

  @override
  String get loadFailed => 'Загрузка не удалась';

  @override
  String get loadDemand => 'Нагрузка';

  @override
  String get loadVsRenewable => 'Нагрузка и генерация';

  @override
  String get loadVsRenewableSubtitle =>
      'Сравнение нагрузки, ВИЭ и импорта из сети';

  @override
  String get localeSection => 'Язык и настройки';

  @override
  String get longitude => 'Долгота';

  @override
  String get mapLegend => 'Нажатие по карте выбирает новую координату';

  @override
  String get mapAnalyticsTitle => 'Навигатор прогноза';

  @override
  String get mapAnalyticsSubtitle =>
      'Переключайтесь между режимами сегодня, 7 дней и 14 дней. Нажатие на столбец открывает подробный профиль дня.';

  @override
  String get mapDraftPointTitle => 'Новая точка готова к добавлению';

  @override
  String get mapDraftPointSubtitle =>
      'Проверьте координаты и откройте форму объекта, чтобы сохранить оборудование в этой позиции.';

  @override
  String get mapTapBarHint =>
      'Нажмите на любой столбец, чтобы открыть детальную страницу суточного прогноза.';

  @override
  String get maxCharge => 'Макс. заряд';

  @override
  String get minCharge => 'Мин. заряд';

  @override
  String get modelVersion => 'Версия модели';

  @override
  String get navDashboard => 'Панель';

  @override
  String get navForecast => 'Прогноз';

  @override
  String get navOptimization => 'Оптимизация';

  @override
  String get navProfile => 'Профиль';

  @override
  String get navSites => 'Объекты';

  @override
  String get netLoad => 'Чистая нагрузка';

  @override
  String get next72Hours => 'Следующие 72 часа';

  @override
  String get next72HoursSubtitle =>
      'Краткосрочное сравнение нагрузки и генерации';

  @override
  String get noSiteMessage =>
      'Сначала добавьте энергетический объект. Он нужен для карты, прогноза и оптимизации.';

  @override
  String get noSiteTitle => 'Объект пока не создан';

  @override
  String get noSitesYet => 'Список объектов пуст';

  @override
  String get noSitesYetMessage =>
      'Добавьте первый солнечный или ветровой объект и сразу запустите серверные прогнозы.';

  @override
  String get notes => 'Примечания';

  @override
  String get onboardingDefaultSiteHint =>
      'После регистрации вы добавите точку на карте и уже там заполните технические параметры, нужные для прогноза.';

  @override
  String get onboardingProfileSection => 'Профиль пользователя';

  @override
  String get onboardingSaveError => 'Не удалось сохранить профиль.';

  @override
  String get onboardingSiteSection => 'Стартовый энергетический объект';

  @override
  String get onboardingSubtitle =>
      'Сначала заполните только основной профиль. Геолокация, мощности и параметры точки прогноза будут добавляться позже на карте.';

  @override
  String get onboardingSuccess =>
      'Профиль успешно сохранён. Следующий шаг: добавить объект на карте.';

  @override
  String get onboardingTitle => 'Первичная настройка';

  @override
  String get optimizationMethodSubtitle =>
      'Параметры сценария передаются в lexicographic dispatch модель.';

  @override
  String get optimizationGuideTitle => 'Как работать с этой страницей';

  @override
  String get optimizationGuideSubtitle =>
      'Следуйте шагам ниже, чтобы настройки батареи и результат оптимизации были понятны и на desktop, и на mobile.';

  @override
  String get optimizationGuideConfigureTitle => 'Настройте окно батареи';

  @override
  String get optimizationGuideConfigureBody =>
      'Перед запуском сценария задайте ёмкость, мощность заряда и разряда, а также допустимый резервный диапазон.';

  @override
  String get optimizationGuideRunTitle => 'Запустите сценарий';

  @override
  String get optimizationGuideRunBody =>
      'После изменения ползунков запустите оптимизацию, чтобы обновить прогноз нагрузки, импорта и SOC для выбранного горизонта.';

  @override
  String get optimizationGuideReviewTitle => 'Проверьте эффект';

  @override
  String get optimizationGuideReviewBody =>
      'Сравните импорт из сети до и после, затем просмотрите кривую нагрузки и SOC батареи, чтобы оценить практичность сценария.';

  @override
  String get optimizationReserveBand => 'Резервный диапазон';

  @override
  String get optimizationSubtitle =>
      'Снижение импорта из сети на основе нагрузки, ВИЭ и сценария батареи';

  @override
  String get optimizationTitle => 'Оптимизация нагрузки';

  @override
  String get openFullscreenMap => 'Открыть карту на весь экран';

  @override
  String get organization => 'Название организации';

  @override
  String get peakRenewable => 'Пиковая генерация';

  @override
  String get phoneNumber => 'Номер телефона';

  @override
  String get preferredLanguage => 'Предпочитаемый язык';

  @override
  String get profileSaveError => 'Не удалось обновить профиль.';

  @override
  String get profileSaved => 'Профиль обновлён.';

  @override
  String get profileSubtitle =>
      'Параметры пользователя, язык и состояние связи с сервером';

  @override
  String get profileTitle => 'Профиль';

  @override
  String get reduction => 'Снижение';

  @override
  String get refresh => 'Обновить';

  @override
  String get refreshForecast => 'Обновить прогноз';

  @override
  String get renewable => 'Возобновляемая энергия';

  @override
  String get renewableTotal => 'Суммарный объём ВИЭ';

  @override
  String get requiredField => 'Это поле обязательно.';

  @override
  String get retry => 'Повторить';

  @override
  String get runOptimization => 'Запустить оптимизацию';

  @override
  String get save => 'Сохранить';

  @override
  String get saveSite => 'Сохранить объект';

  @override
  String get selectedSite => 'Выбранный объект';

  @override
  String get selfSufficiency => 'Самообеспечение';

  @override
  String get serverModel => 'Серверная модель';

  @override
  String get setAsDefault => 'Сделать основным';

  @override
  String get shellSubtitle =>
      'Контроль генерации, нагрузки и энергетической устойчивости Smart City в одном интерфейсе';

  @override
  String get signOut => 'Выйти';

  @override
  String get signOutConfirmTitle => 'Подтвердите выход';

  @override
  String get signOutConfirmMessage =>
      'Текущая сессия будет завершена на этом устройстве. После этого потребуется повторный вход по номеру телефона.';

  @override
  String get signOutConfirmAction => 'Выйти из аккаунта';

  @override
  String get signOutStay => 'Остаться в системе';

  @override
  String get signedInPhone => 'Телефон входа';

  @override
  String get siteDeleted => 'Объект удалён.';

  @override
  String get closeFullscreenMap => 'Выйти из полноэкранной карты';

  @override
  String get siteFormTitleEdit => 'Редактирование объекта';

  @override
  String get siteFormTitleNew => 'Новый объект';

  @override
  String get siteList => 'Список объектов';

  @override
  String get siteListSubtitle => 'Параметры солнца, ветра и батареи';

  @override
  String get siteName => 'Название объекта';

  @override
  String get sitePreferences => 'Основной объект и язык';

  @override
  String get siteSaved => 'Объект сохранён.';

  @override
  String get sitesTitle => 'Карта объектов';

  @override
  String get solarCapacity => 'Солнечная мощность';

  @override
  String get solarRadiation => 'Солнечная радиация';

  @override
  String get solarTotal => 'Солнечная генерация';

  @override
  String get shellBadge => 'Управление ВИЭ';

  @override
  String get systemStatus => 'Состояние системы';

  @override
  String get tapMapToSelect =>
      'Нажмите на карту, чтобы выбрать координату. Затем её можно использовать в диалоге создания объекта.';

  @override
  String get today => 'Сегодня';

  @override
  String get tilt => 'Угол наклона';

  @override
  String get unknown => 'Неизвестно';

  @override
  String get userRoleLabel => 'Пользователь Smart City';

  @override
  String get userOnlyWorkspace =>
      'Рабочее пространство только для пользователя';

  @override
  String get weatherWindow => 'Климатическое окно';

  @override
  String get weatherWindowSubtitle =>
      'Краткосрочные климатические индикаторы по данным Open-Meteo';

  @override
  String get windCapacity => 'Ветровая мощность';

  @override
  String get windHubHeight => 'Высота хаба';

  @override
  String get windSpeed => 'Скорость ветра';

  @override
  String get windTotal => 'Ветровая генерация';

  @override
  String get weatherVariant => 'Погодная версия';

  @override
  String get qualityInputs => 'Контроль погоды';

  @override
  String get qualityAttention => 'есть отклонения от обучающей выборки';

  @override
  String get qualityReference => 'в пределах опорного диапазона';

  @override
  String get siteEnergyEstimate =>
      'Расчёт энергии по погоде и мощности установки; без калибровки по измерениям объекта.';
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_kk.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('kk'),
    Locale('ru'),
  ];

  /// No description provided for @accountSection.
  ///
  /// In kk, this message translates to:
  /// **'Тіркелгі деректері'**
  String get accountSection;

  /// No description provided for @accountUid.
  ///
  /// In kk, this message translates to:
  /// **'Пайдаланушы ID'**
  String get accountUid;

  /// No description provided for @activeSite.
  ///
  /// In kk, this message translates to:
  /// **'Белсенді нысан'**
  String get activeSite;

  /// No description provided for @addSite.
  ///
  /// In kk, this message translates to:
  /// **'Нысан қосу'**
  String get addSite;

  /// No description provided for @address.
  ///
  /// In kk, this message translates to:
  /// **'Мекенжай'**
  String get address;

  /// No description provided for @appTagline.
  ///
  /// In kk, this message translates to:
  /// **'Smart City үшін жаңартылатын энергияны болжау және жүктемені оңтайландыру платформасы'**
  String get appTagline;

  /// No description provided for @appTitle.
  ///
  /// In kk, this message translates to:
  /// **'Smart City Renewable AI'**
  String get appTitle;

  /// No description provided for @authBack.
  ///
  /// In kk, this message translates to:
  /// **'Кері'**
  String get authBack;

  /// No description provided for @authAutoVerifyHint.
  ///
  /// In kk, this message translates to:
  /// **'Код толық енгізілгеннен кейін растау автоматты түрде жалғасады.'**
  String get authAutoVerifyHint;

  /// No description provided for @authBenefitForecast.
  ///
  /// In kk, this message translates to:
  /// **'Күн және жел генерациясы бойынша 7 және 14 күндік кәсіби болжамдар'**
  String get authBenefitForecast;

  /// No description provided for @authBenefitMap.
  ///
  /// In kk, this message translates to:
  /// **'Нысандарды картада басқару және әр локацияны жеке бейімдеу'**
  String get authBenefitMap;

  /// No description provided for @authBenefitOptimization.
  ///
  /// In kk, this message translates to:
  /// **'Жүктеме, батарея және энергия балансына арналған оңтайландыру панельдері'**
  String get authBenefitOptimization;

  /// No description provided for @authChangePhone.
  ///
  /// In kk, this message translates to:
  /// **'Нөмірді өзгерту'**
  String get authChangePhone;

  /// No description provided for @authCodeSentBadge.
  ///
  /// In kk, this message translates to:
  /// **'Код жіберілді'**
  String get authCodeSentBadge;

  /// No description provided for @authCodeHint.
  ///
  /// In kk, this message translates to:
  /// **'6 таңбалы SMS кодын енгізіңіз'**
  String get authCodeHint;

  /// No description provided for @authCodeLabel.
  ///
  /// In kk, this message translates to:
  /// **'Растау коды'**
  String get authCodeLabel;

  /// No description provided for @authErrorSendCode.
  ///
  /// In kk, this message translates to:
  /// **'Кодты жіберу мүмкін болмады. Қайтадан көріңіз.'**
  String get authErrorSendCode;

  /// No description provided for @authErrorVerify.
  ///
  /// In kk, this message translates to:
  /// **'Кодты тексеру сәтсіз аяқталды.'**
  String get authErrorVerify;

  /// No description provided for @authHeroSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Астана жағдайына бейімделген күн және жел энергетикасын басқаруға арналған бірыңғай цифрлық орта.'**
  String get authHeroSubtitle;

  /// No description provided for @authHeroTitle.
  ///
  /// In kk, this message translates to:
  /// **'Жаңартылатын энергияны дәл басқаратын пайдаланушы кабинеті'**
  String get authHeroTitle;

  /// No description provided for @authInvalidPhone.
  ///
  /// In kk, this message translates to:
  /// **'Дұрыс телефон нөмірін енгізіңіз.'**
  String get authInvalidPhone;

  /// No description provided for @authOtpSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'{phone} нөміріне жіберілген растау кодын енгізіңіз.'**
  String authOtpSubtitle(Object phone);

  /// No description provided for @authOtpTitle.
  ///
  /// In kk, this message translates to:
  /// **'Кіруді растау'**
  String get authOtpTitle;

  /// No description provided for @authOtpSent.
  ///
  /// In kk, this message translates to:
  /// **'Код жіберілді. Кіруді жалғастырыңыз.'**
  String get authOtpSent;

  /// No description provided for @authPhoneEntryDescription.
  ///
  /// In kk, this message translates to:
  /// **'Жеке кабинетке кіру үшін телефон нөміріңізді енгізіңіз.'**
  String get authPhoneEntryDescription;

  /// No description provided for @authPhoneHint.
  ///
  /// In kk, this message translates to:
  /// **'700 000 00 00'**
  String get authPhoneHint;

  /// No description provided for @authPhoneLabel.
  ///
  /// In kk, this message translates to:
  /// **'Телефон нөмірі'**
  String get authPhoneLabel;

  /// No description provided for @authSendCode.
  ///
  /// In kk, this message translates to:
  /// **'Код жіберу'**
  String get authSendCode;

  /// No description provided for @authSmsHelper.
  ///
  /// In kk, this message translates to:
  /// **''**
  String get authSmsHelper;

  /// No description provided for @authSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Жүйеге телефон нөмірі арқылы кіріңіз. Бірінші кіруден кейін тек негізгі профиль толтырылады, ал нысан параметрлері карта бөлімінде қосылады.'**
  String get authSubtitle;

  /// No description provided for @authTitle.
  ///
  /// In kk, this message translates to:
  /// **'Жеке кабинетке кіру'**
  String get authTitle;

  /// No description provided for @authVerifyingCode.
  ///
  /// In kk, this message translates to:
  /// **'Код тексеріліп жатыр'**
  String get authVerifyingCode;

  /// No description provided for @authVerify.
  ///
  /// In kk, this message translates to:
  /// **'Растап кіру'**
  String get authVerify;

  /// No description provided for @averageRisk.
  ///
  /// In kk, this message translates to:
  /// **'Модель бағасы, апат ықтималдығы емес'**
  String get averageRisk;

  /// No description provided for @azimuth.
  ///
  /// In kk, this message translates to:
  /// **'Азимут'**
  String get azimuth;

  /// No description provided for @backupEmail.
  ///
  /// In kk, this message translates to:
  /// **'Резервтік e-mail'**
  String get backupEmail;

  /// No description provided for @backToForecast.
  ///
  /// In kk, this message translates to:
  /// **'Болжамға оралу'**
  String get backToForecast;

  /// No description provided for @batteryCapacity.
  ///
  /// In kk, this message translates to:
  /// **'Батарея сыйымдылығы'**
  String get batteryCapacity;

  /// No description provided for @batteryEnabled.
  ///
  /// In kk, this message translates to:
  /// **'Батарея сценарийін қосу'**
  String get batteryEnabled;

  /// No description provided for @batteryScenario.
  ///
  /// In kk, this message translates to:
  /// **'Батарея сценарийі'**
  String get batteryScenario;

  /// No description provided for @batterySoc.
  ///
  /// In kk, this message translates to:
  /// **'Батарея заряды'**
  String get batterySoc;

  /// No description provided for @batterySocSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Уақыт бойынша SOC профилі'**
  String get batterySocSubtitle;

  /// No description provided for @cancel.
  ///
  /// In kk, this message translates to:
  /// **'Бас тарту'**
  String get cancel;

  /// No description provided for @chargePower.
  ///
  /// In kk, this message translates to:
  /// **'Заряд қуаты'**
  String get chargePower;

  /// No description provided for @city.
  ///
  /// In kk, this message translates to:
  /// **'Қала'**
  String get city;

  /// No description provided for @completeRegistration.
  ///
  /// In kk, this message translates to:
  /// **'Тіркеуді аяқтау'**
  String get completeRegistration;

  /// No description provided for @connectedServer.
  ///
  /// In kk, this message translates to:
  /// **'Қосылған сервер'**
  String get connectedServer;

  /// No description provided for @currentTemperature.
  ///
  /// In kk, this message translates to:
  /// **'Температура'**
  String get currentTemperature;

  /// No description provided for @dailyBreakdown.
  ///
  /// In kk, this message translates to:
  /// **'Күндік бөлініс'**
  String get dailyBreakdown;

  /// No description provided for @dailyBreakdownSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Күн және жел генерациясының тәуліктік құрылымы'**
  String get dailyBreakdownSubtitle;

  /// No description provided for @dashboardHeroSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Бұл панель нысанның ағымдағы болжамын, климаттық жағдайын және энергия жүйесінің қысқаша күйін бір жерге жинайды.'**
  String get dashboardHeroSubtitle;

  /// No description provided for @dashboardHeroTitle.
  ///
  /// In kk, this message translates to:
  /// **'Энергетикалық жағдайдың қысқаша шолуы'**
  String get dashboardHeroTitle;

  /// No description provided for @dashboardSiteControlSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Панель күйін анықтайтын орнатылған нүктені таңдаңыз.'**
  String get dashboardSiteControlSubtitle;

  /// No description provided for @dashboardInstalledPoints.
  ///
  /// In kk, this message translates to:
  /// **'Орнатылған нүктелер'**
  String get dashboardInstalledPoints;

  /// No description provided for @dashboardDefaultSiteSaved.
  ///
  /// In kk, this message translates to:
  /// **'Негізгі нысан жаңартылды.'**
  String get dashboardDefaultSiteSaved;

  /// No description provided for @dashboardDefaultSiteSaveError.
  ///
  /// In kk, this message translates to:
  /// **'Негізгі нысанды жаңарту мүмкін болмады.'**
  String get dashboardDefaultSiteSaveError;

  /// No description provided for @dashboardOperationalFocusTitle.
  ///
  /// In kk, this message translates to:
  /// **'Операциялық фокус'**
  String get dashboardOperationalFocusTitle;

  /// No description provided for @dashboardOperationalFocusSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Болжам, климат және энергия балансы негізіндегі ықшам сараптамалық шолу.'**
  String get dashboardOperationalFocusSubtitle;

  /// No description provided for @dashboardRecommendedAction.
  ///
  /// In kk, this message translates to:
  /// **'Ұсынылатын әрекет'**
  String get dashboardRecommendedAction;

  /// No description provided for @dashboardPeakWindow.
  ///
  /// In kk, this message translates to:
  /// **'Пиктік терезе'**
  String get dashboardPeakWindow;

  /// No description provided for @dashboardCoverageMode.
  ///
  /// In kk, this message translates to:
  /// **'Қамту режимі'**
  String get dashboardCoverageMode;

  /// No description provided for @dashboardStableMode.
  ///
  /// In kk, this message translates to:
  /// **'Тұрақты ВИЭ терезесі'**
  String get dashboardStableMode;

  /// No description provided for @dashboardSolarMode.
  ///
  /// In kk, this message translates to:
  /// **'Күн басым интервал'**
  String get dashboardSolarMode;

  /// No description provided for @dashboardWindMode.
  ///
  /// In kk, this message translates to:
  /// **'Жел қолдайтын интервал'**
  String get dashboardWindMode;

  /// No description provided for @dashboardGridMode.
  ///
  /// In kk, this message translates to:
  /// **'Желі қолдауы қажет'**
  String get dashboardGridMode;

  /// No description provided for @dashboardStableAction.
  ///
  /// In kk, this message translates to:
  /// **'Икемді жүктемені ВИЭ пигіне ығыстырып, кешкі уақыт үшін батарея қорын сақтаңыз.'**
  String get dashboardStableAction;

  /// No description provided for @dashboardSolarAction.
  ///
  /// In kk, this message translates to:
  /// **'Күндізгі генерация терезесін энергияны көп қажет ететін процестерге және батареяны зарядтауға пайдаланыңыз.'**
  String get dashboardSolarAction;

  /// No description provided for @dashboardWindAction.
  ///
  /// In kk, this message translates to:
  /// **'Қысқа мерзімді құбылмалылықты тегістеу үшін жел генерациясы мен жинақтағыш арасындағы теңгерімді сақтаңыз.'**
  String get dashboardWindAction;

  /// No description provided for @dashboardGridAction.
  ///
  /// In kk, this message translates to:
  /// **'Критикалық жүктемелерді басымдыққа қойып, генерация жақсарғанша батарея резервін сақтаңыз.'**
  String get dashboardGridAction;

  /// No description provided for @dashboardGridDependency.
  ///
  /// In kk, this message translates to:
  /// **'Желіге тәуелділік'**
  String get dashboardGridDependency;

  /// No description provided for @dashboardGridDependencyHint.
  ///
  /// In kk, this message translates to:
  /// **'Сұраныстың қазіргі сәтте сыртқы желі импортымен жабылып жатқан үлесі'**
  String get dashboardGridDependencyHint;

  /// No description provided for @day.
  ///
  /// In kk, this message translates to:
  /// **'Күн'**
  String get day;

  /// No description provided for @day14.
  ///
  /// In kk, this message translates to:
  /// **'14 күн'**
  String get day14;

  /// No description provided for @day7.
  ///
  /// In kk, this message translates to:
  /// **'7 күн'**
  String get day7;

  /// No description provided for @defaultSite.
  ///
  /// In kk, this message translates to:
  /// **'Негізгі нысан'**
  String get defaultSite;

  /// No description provided for @delete.
  ///
  /// In kk, this message translates to:
  /// **'Жою'**
  String get delete;

  /// No description provided for @deleteSiteConfirm.
  ///
  /// In kk, this message translates to:
  /// **'Бұл нысанды шынымен жойғыңыз келе ме?'**
  String get deleteSiteConfirm;

  /// No description provided for @dischargePower.
  ///
  /// In kk, this message translates to:
  /// **'Разряд қуаты'**
  String get dischargePower;

  /// No description provided for @edit.
  ///
  /// In kk, this message translates to:
  /// **'Өңдеу'**
  String get edit;

  /// No description provided for @energyMix.
  ///
  /// In kk, this message translates to:
  /// **'Генерация құрылымы'**
  String get energyMix;

  /// No description provided for @extremeRisk.
  ///
  /// In kk, this message translates to:
  /// **'Жоғары генерация индексі'**
  String get extremeRisk;

  /// No description provided for @fetchErrorGeneric.
  ///
  /// In kk, this message translates to:
  /// **'Серверден деректерді жүктеу кезінде қате пайда болды.'**
  String get fetchErrorGeneric;

  /// No description provided for @forecast14Day.
  ///
  /// In kk, this message translates to:
  /// **'14 күндік болжам'**
  String get forecast14Day;

  /// No description provided for @forecast7Day.
  ///
  /// In kk, this message translates to:
  /// **'7 күндік болжам'**
  String get forecast7Day;

  /// No description provided for @forecastDayDetailTitle.
  ///
  /// In kk, this message translates to:
  /// **'Таңдалған күн профилі'**
  String get forecastDayDetailTitle;

  /// No description provided for @forecastDayDetailSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'15 минуттық қадаммен берілетін егжей-тегжейлі күн ішіндегі генерация профилі.'**
  String get forecastDayDetailSubtitle;

  /// No description provided for @forecastDayUnavailable.
  ///
  /// In kk, this message translates to:
  /// **'Таңдалған күн белсенді болжам ауқымында қолжетімсіз.'**
  String get forecastDayUnavailable;

  /// No description provided for @forecastDetailInsightTitle.
  ///
  /// In kk, this message translates to:
  /// **'Таңдалған нүктені талдау'**
  String get forecastDetailInsightTitle;

  /// No description provided for @forecastDetailInsightSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Күндік графиктегі бекітілген нүктеге арналған операциялық түсіндірме.'**
  String get forecastDetailInsightSubtitle;

  /// No description provided for @forecastOpenDay.
  ///
  /// In kk, this message translates to:
  /// **'Күнді толық ашу'**
  String get forecastOpenDay;

  /// No description provided for @forecastOpenDaySubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Толық күн ішіндегі профильді көру үшін графиктен не кестеден күнді басыңыз.'**
  String get forecastOpenDaySubtitle;

  /// No description provided for @forecastPageTitle.
  ///
  /// In kk, this message translates to:
  /// **'Толық генерация болжамы'**
  String get forecastPageTitle;

  /// No description provided for @forecastPointRecommendation.
  ///
  /// In kk, this message translates to:
  /// **'Ұсынылатын әрекет'**
  String get forecastPointRecommendation;

  /// No description provided for @forecastPointRisk.
  ///
  /// In kk, this message translates to:
  /// **'Осы сағаттағы индекс'**
  String get forecastPointRisk;

  /// No description provided for @forecastPointTime.
  ///
  /// In kk, this message translates to:
  /// **'Уақыт'**
  String get forecastPointTime;

  /// No description provided for @forecastRecommendationRisk.
  ///
  /// In kk, this message translates to:
  /// **'Модель жоғары генерацияны көрсетеді. Болжамды жүктемемен және батареяның қолжетімді сыйымдылығымен салыстырыңыз.'**
  String get forecastRecommendationRisk;

  /// No description provided for @forecastRecommendationSolar.
  ///
  /// In kk, this message translates to:
  /// **'Күшті күн интервалын икемді күндізгі процестер мен батареяны зарядтауға пайдаланыңыз.'**
  String get forecastRecommendationSolar;

  /// No description provided for @forecastRecommendationStable.
  ///
  /// In kk, this message translates to:
  /// **'ВИЭ профилі теңгерімді. Қалыпты режимді сақтап, келесі ауысу терезесін бақылаңыз.'**
  String get forecastRecommendationStable;

  /// No description provided for @forecastRecommendationWind.
  ///
  /// In kk, this message translates to:
  /// **'Жел қолдауы жоғары. Жинақтағыш арқылы профильді тегістеп, жүктеменің күрт өзгеруін болдырмаңыз.'**
  String get forecastRecommendationWind;

  /// No description provided for @forecastTable.
  ///
  /// In kk, this message translates to:
  /// **'Күндік кесте'**
  String get forecastTable;

  /// No description provided for @forecastTableSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Жиынтық мәндер мен тәуліктік үлес'**
  String get forecastTableSubtitle;

  /// No description provided for @forecastTapDayHint.
  ///
  /// In kk, this message translates to:
  /// **'Күнді таңдау профильдің егжей-тегжейлі бетіне апарады.'**
  String get forecastTapDayHint;

  /// No description provided for @fullName.
  ///
  /// In kk, this message translates to:
  /// **'Т.А.Ә.'**
  String get fullName;

  /// No description provided for @goToSites.
  ///
  /// In kk, this message translates to:
  /// **'Нысандар бетіне өту'**
  String get goToSites;

  /// No description provided for @gridImportAfter.
  ///
  /// In kk, this message translates to:
  /// **'Желі импорты кейін'**
  String get gridImportAfter;

  /// No description provided for @gridImportBefore.
  ///
  /// In kk, this message translates to:
  /// **'Желі импорты дейін'**
  String get gridImportBefore;

  /// No description provided for @healthStatus.
  ///
  /// In kk, this message translates to:
  /// **'Қызмет күйі'**
  String get healthStatus;

  /// No description provided for @hourlyCurve.
  ///
  /// In kk, this message translates to:
  /// **'Сағаттық қисық'**
  String get hourlyCurve;

  /// No description provided for @hourlyCurveSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Алдағы 72 сағаттағы күн, жел және жиынтық генерация'**
  String get hourlyCurveSubtitle;

  /// No description provided for @humidity.
  ///
  /// In kk, this message translates to:
  /// **'Ылғалдылық'**
  String get humidity;

  /// No description provided for @initialCharge.
  ///
  /// In kk, this message translates to:
  /// **'Бастапқы заряд'**
  String get initialCharge;

  /// No description provided for @initialSiteNameDefault.
  ///
  /// In kk, this message translates to:
  /// **'Астана негізгі нысаны'**
  String get initialSiteNameDefault;

  /// No description provided for @invalidEmail.
  ///
  /// In kk, this message translates to:
  /// **'E-mail пішімі қате.'**
  String get invalidEmail;

  /// No description provided for @invalidNumber.
  ///
  /// In kk, this message translates to:
  /// **'Сандық мән енгізіңіз.'**
  String get invalidNumber;

  /// No description provided for @language.
  ///
  /// In kk, this message translates to:
  /// **'Тіл'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In kk, this message translates to:
  /// **'Ағылшынша'**
  String get languageEnglish;

  /// No description provided for @languageKazakh.
  ///
  /// In kk, this message translates to:
  /// **'Қазақша'**
  String get languageKazakh;

  /// No description provided for @languageRussian.
  ///
  /// In kk, this message translates to:
  /// **'Орысша'**
  String get languageRussian;

  /// No description provided for @languageShortEnglish.
  ///
  /// In kk, this message translates to:
  /// **'ENG'**
  String get languageShortEnglish;

  /// No description provided for @languageShortKazakh.
  ///
  /// In kk, this message translates to:
  /// **'ҚАЗ'**
  String get languageShortKazakh;

  /// No description provided for @languageShortRussian.
  ///
  /// In kk, this message translates to:
  /// **'ОРЫС'**
  String get languageShortRussian;

  /// No description provided for @latitude.
  ///
  /// In kk, this message translates to:
  /// **'Ендік'**
  String get latitude;

  /// No description provided for @lastUpdatedLabel.
  ///
  /// In kk, this message translates to:
  /// **'Соңғы жаңарту күні'**
  String get lastUpdatedLabel;

  /// No description provided for @loadFailed.
  ///
  /// In kk, this message translates to:
  /// **'Жүктеу сәтсіз'**
  String get loadFailed;

  /// No description provided for @loadDemand.
  ///
  /// In kk, this message translates to:
  /// **'Жүктеме'**
  String get loadDemand;

  /// No description provided for @loadVsRenewable.
  ///
  /// In kk, this message translates to:
  /// **'Жүктеме және генерация'**
  String get loadVsRenewable;

  /// No description provided for @loadVsRenewableSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Жүктеме, ВИЭ және желі импортының салыстырмасы'**
  String get loadVsRenewableSubtitle;

  /// No description provided for @localeSection.
  ///
  /// In kk, this message translates to:
  /// **'Тіл және теңшелімдер'**
  String get localeSection;

  /// No description provided for @longitude.
  ///
  /// In kk, this message translates to:
  /// **'Бойлық'**
  String get longitude;

  /// No description provided for @mapLegend.
  ///
  /// In kk, this message translates to:
  /// **'Картадағы басу жаңа координатаны таңдайды'**
  String get mapLegend;

  /// No description provided for @mapAnalyticsTitle.
  ///
  /// In kk, this message translates to:
  /// **'Болжам навигаторы'**
  String get mapAnalyticsTitle;

  /// No description provided for @mapAnalyticsSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Бүгін, 7 күн және 14 күн режимдерін ауыстырыңыз. Бағанды басу күннің толық профилін ашады.'**
  String get mapAnalyticsSubtitle;

  /// No description provided for @mapDraftPointTitle.
  ///
  /// In kk, this message translates to:
  /// **'Жаңа нүкте қосуға дайын'**
  String get mapDraftPointTitle;

  /// No description provided for @mapDraftPointSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Координаталарды тексеріп, осы орынға жабдықты сақтау үшін нысан формасын ашыңыз.'**
  String get mapDraftPointSubtitle;

  /// No description provided for @mapTapBarHint.
  ///
  /// In kk, this message translates to:
  /// **'Күндік болжамның толық бетіне өту үшін кез келген бағанды басыңыз.'**
  String get mapTapBarHint;

  /// No description provided for @maxCharge.
  ///
  /// In kk, this message translates to:
  /// **'Макс. заряд'**
  String get maxCharge;

  /// No description provided for @minCharge.
  ///
  /// In kk, this message translates to:
  /// **'Мин. заряд'**
  String get minCharge;

  /// No description provided for @modelVersion.
  ///
  /// In kk, this message translates to:
  /// **'Модель нұсқасы'**
  String get modelVersion;

  /// No description provided for @navDashboard.
  ///
  /// In kk, this message translates to:
  /// **'Басқару панелі'**
  String get navDashboard;

  /// No description provided for @navForecast.
  ///
  /// In kk, this message translates to:
  /// **'Болжам'**
  String get navForecast;

  /// No description provided for @navOptimization.
  ///
  /// In kk, this message translates to:
  /// **'Оңтайландыру'**
  String get navOptimization;

  /// No description provided for @navProfile.
  ///
  /// In kk, this message translates to:
  /// **'Профиль'**
  String get navProfile;

  /// No description provided for @navSites.
  ///
  /// In kk, this message translates to:
  /// **'Нысандар'**
  String get navSites;

  /// No description provided for @netLoad.
  ///
  /// In kk, this message translates to:
  /// **'Таза жүктеме'**
  String get netLoad;

  /// No description provided for @next72Hours.
  ///
  /// In kk, this message translates to:
  /// **'Келесі 72 сағат'**
  String get next72Hours;

  /// No description provided for @next72HoursSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Жүктеме мен генерацияның қысқа мерзімді салыстырмасы'**
  String get next72HoursSubtitle;

  /// No description provided for @noSiteMessage.
  ///
  /// In kk, this message translates to:
  /// **'Алдымен энергетикалық нысанды қосыңыз. Ол карта, болжам және оңтайландыру бөлімдері үшін қажет.'**
  String get noSiteMessage;

  /// No description provided for @noSiteTitle.
  ///
  /// In kk, this message translates to:
  /// **'Нысан әзірше жоқ'**
  String get noSiteTitle;

  /// No description provided for @noSitesYet.
  ///
  /// In kk, this message translates to:
  /// **'Нысандар тізімі бос'**
  String get noSitesYet;

  /// No description provided for @noSitesYetMessage.
  ///
  /// In kk, this message translates to:
  /// **'Бірінші күн/жел нысанын қосып, серверлік болжамдарды бірден іске қосыңыз.'**
  String get noSitesYetMessage;

  /// No description provided for @notes.
  ///
  /// In kk, this message translates to:
  /// **'Ескертпелер'**
  String get notes;

  /// No description provided for @onboardingDefaultSiteHint.
  ///
  /// In kk, this message translates to:
  /// **'Тіркеуден кейін карта бетінде нүкте қосып, сол жерде болжауға қажетті техникалық параметрлерді толтырасыз.'**
  String get onboardingDefaultSiteHint;

  /// No description provided for @onboardingProfileSection.
  ///
  /// In kk, this message translates to:
  /// **'Пайдаланушы профилі'**
  String get onboardingProfileSection;

  /// No description provided for @onboardingSaveError.
  ///
  /// In kk, this message translates to:
  /// **'Профильді сақтау сәтсіз аяқталды.'**
  String get onboardingSaveError;

  /// No description provided for @onboardingSiteSection.
  ///
  /// In kk, this message translates to:
  /// **'Бастапқы энергетикалық нысан'**
  String get onboardingSiteSection;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Алдымен тек негізгі профильді толтырыңыз. Геолокация, қуаттар және болжау нүктесінің параметрлері кейін карта бөлімінде қосылады.'**
  String get onboardingSubtitle;

  /// No description provided for @onboardingSuccess.
  ///
  /// In kk, this message translates to:
  /// **'Профиль сәтті сақталды. Келесі қадам: картада нысан қосу.'**
  String get onboardingSuccess;

  /// No description provided for @onboardingTitle.
  ///
  /// In kk, this message translates to:
  /// **'Бастапқы баптау'**
  String get onboardingTitle;

  /// No description provided for @optimizationMethodSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Сценарий параметрлері lexicographic dispatch моделіне жіберіледі.'**
  String get optimizationMethodSubtitle;

  /// No description provided for @optimizationGuideTitle.
  ///
  /// In kk, this message translates to:
  /// **'Бұл бетпен қалай жұмыс істеу керек'**
  String get optimizationGuideTitle;

  /// No description provided for @optimizationGuideSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Батарея параметрлері мен оңтайландыру нәтижесі desktop пен mobile нұсқаларында бірдей түсінікті болуы үшін төмендегі реттілікті қолданыңыз.'**
  String get optimizationGuideSubtitle;

  /// No description provided for @optimizationGuideConfigureTitle.
  ///
  /// In kk, this message translates to:
  /// **'Батарея терезесін баптаңыз'**
  String get optimizationGuideConfigureTitle;

  /// No description provided for @optimizationGuideConfigureBody.
  ///
  /// In kk, this message translates to:
  /// **'Сценарийді іске қоспас бұрын сыйымдылықты, заряд/разряд қуатын және рұқсат етілген резерв диапазонын орнатыңыз.'**
  String get optimizationGuideConfigureBody;

  /// No description provided for @optimizationGuideRunTitle.
  ///
  /// In kk, this message translates to:
  /// **'Сценарийді іске қосыңыз'**
  String get optimizationGuideRunTitle;

  /// No description provided for @optimizationGuideRunBody.
  ///
  /// In kk, this message translates to:
  /// **'Ползуноктарды өзгерткеннен кейін таңдалған көкжиек үшін жүктеме, импорт және SOC болжамын жаңарту мақсатында оңтайландыруды іске қосыңыз.'**
  String get optimizationGuideRunBody;

  /// No description provided for @optimizationGuideReviewTitle.
  ///
  /// In kk, this message translates to:
  /// **'Нәтижені тексеріңіз'**
  String get optimizationGuideReviewTitle;

  /// No description provided for @optimizationGuideReviewBody.
  ///
  /// In kk, this message translates to:
  /// **'Желі импортының дейінгі және кейінгі мәндерін салыстырып, одан кейін сценарийдің практикалығын бағалау үшін жүктеме қисығы мен батарея SOC-ын қараңыз.'**
  String get optimizationGuideReviewBody;

  /// No description provided for @optimizationReserveBand.
  ///
  /// In kk, this message translates to:
  /// **'Резерв диапазоны'**
  String get optimizationReserveBand;

  /// No description provided for @optimizationSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Жүктеме, ВИЭ және батарея сценарийі бойынша желіден импортты азайту'**
  String get optimizationSubtitle;

  /// No description provided for @optimizationTitle.
  ///
  /// In kk, this message translates to:
  /// **'Жүктемені оңтайландыру'**
  String get optimizationTitle;

  /// No description provided for @openFullscreenMap.
  ///
  /// In kk, this message translates to:
  /// **'Картаны толық ашу'**
  String get openFullscreenMap;

  /// No description provided for @organization.
  ///
  /// In kk, this message translates to:
  /// **'Ұйым атауы'**
  String get organization;

  /// No description provided for @peakRenewable.
  ///
  /// In kk, this message translates to:
  /// **'Пиктік генерация'**
  String get peakRenewable;

  /// No description provided for @phoneNumber.
  ///
  /// In kk, this message translates to:
  /// **'Телефон нөмірі'**
  String get phoneNumber;

  /// No description provided for @preferredLanguage.
  ///
  /// In kk, this message translates to:
  /// **'Таңдаулы тіл'**
  String get preferredLanguage;

  /// No description provided for @profileSaveError.
  ///
  /// In kk, this message translates to:
  /// **'Профильді жаңарту мүмкін болмады.'**
  String get profileSaveError;

  /// No description provided for @profileSaved.
  ///
  /// In kk, this message translates to:
  /// **'Профиль жаңартылды.'**
  String get profileSaved;

  /// No description provided for @profileSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Пайдаланушы параметрлері, тіл және сервермен байланыс күйі'**
  String get profileSubtitle;

  /// No description provided for @profileTitle.
  ///
  /// In kk, this message translates to:
  /// **'Профиль'**
  String get profileTitle;

  /// No description provided for @reduction.
  ///
  /// In kk, this message translates to:
  /// **'Қысқарту'**
  String get reduction;

  /// No description provided for @refresh.
  ///
  /// In kk, this message translates to:
  /// **'Жаңарту'**
  String get refresh;

  /// No description provided for @refreshForecast.
  ///
  /// In kk, this message translates to:
  /// **'Болжамды жаңарту'**
  String get refreshForecast;

  /// No description provided for @renewable.
  ///
  /// In kk, this message translates to:
  /// **'Жаңартылатын энергия'**
  String get renewable;

  /// No description provided for @renewableTotal.
  ///
  /// In kk, this message translates to:
  /// **'Жалпы ВИЭ көлемі'**
  String get renewableTotal;

  /// No description provided for @requiredField.
  ///
  /// In kk, this message translates to:
  /// **'Бұл өріс міндетті.'**
  String get requiredField;

  /// No description provided for @retry.
  ///
  /// In kk, this message translates to:
  /// **'Қайталау'**
  String get retry;

  /// No description provided for @runOptimization.
  ///
  /// In kk, this message translates to:
  /// **'Оңтайландыруды іске қосу'**
  String get runOptimization;

  /// No description provided for @save.
  ///
  /// In kk, this message translates to:
  /// **'Сақтау'**
  String get save;

  /// No description provided for @saveSite.
  ///
  /// In kk, this message translates to:
  /// **'Нысанды сақтау'**
  String get saveSite;

  /// No description provided for @selectedSite.
  ///
  /// In kk, this message translates to:
  /// **'Таңдалған нысан'**
  String get selectedSite;

  /// No description provided for @selfSufficiency.
  ///
  /// In kk, this message translates to:
  /// **'Өзін-өзі қамту'**
  String get selfSufficiency;

  /// No description provided for @serverModel.
  ///
  /// In kk, this message translates to:
  /// **'Сервер моделі'**
  String get serverModel;

  /// No description provided for @setAsDefault.
  ///
  /// In kk, this message translates to:
  /// **'Негізгі ету'**
  String get setAsDefault;

  /// No description provided for @shellSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Smart City үшін генерация, жүктеме және энергетикалық тұрақтылықты бір кеңістікте бақылау'**
  String get shellSubtitle;

  /// No description provided for @signOut.
  ///
  /// In kk, this message translates to:
  /// **'Шығу'**
  String get signOut;

  /// No description provided for @signOutConfirmTitle.
  ///
  /// In kk, this message translates to:
  /// **'Шығуды растаңыз'**
  String get signOutConfirmTitle;

  /// No description provided for @signOutConfirmMessage.
  ///
  /// In kk, this message translates to:
  /// **'Осы құрылғыдағы ағымдағы сессия жабылады. Осыдан кейін телефон нөмірі арқылы қайта кіру қажет болады.'**
  String get signOutConfirmMessage;

  /// No description provided for @signOutConfirmAction.
  ///
  /// In kk, this message translates to:
  /// **'Аккаунттан шығу'**
  String get signOutConfirmAction;

  /// No description provided for @signOutStay.
  ///
  /// In kk, this message translates to:
  /// **'Жүйеде қалу'**
  String get signOutStay;

  /// No description provided for @signedInPhone.
  ///
  /// In kk, this message translates to:
  /// **'Кіру телефоны'**
  String get signedInPhone;

  /// No description provided for @siteDeleted.
  ///
  /// In kk, this message translates to:
  /// **'Нысан жойылды.'**
  String get siteDeleted;

  /// No description provided for @closeFullscreenMap.
  ///
  /// In kk, this message translates to:
  /// **'Толық экраннан шығу'**
  String get closeFullscreenMap;

  /// No description provided for @siteFormTitleEdit.
  ///
  /// In kk, this message translates to:
  /// **'Нысанды өңдеу'**
  String get siteFormTitleEdit;

  /// No description provided for @siteFormTitleNew.
  ///
  /// In kk, this message translates to:
  /// **'Жаңа нысан'**
  String get siteFormTitleNew;

  /// No description provided for @siteList.
  ///
  /// In kk, this message translates to:
  /// **'Нысандар тізімі'**
  String get siteList;

  /// No description provided for @siteListSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Күн, жел және батарея параметрлері'**
  String get siteListSubtitle;

  /// No description provided for @siteName.
  ///
  /// In kk, this message translates to:
  /// **'Нысан атауы'**
  String get siteName;

  /// No description provided for @sitePreferences.
  ///
  /// In kk, this message translates to:
  /// **'Әдепкі нысан және тіл'**
  String get sitePreferences;

  /// No description provided for @siteSaved.
  ///
  /// In kk, this message translates to:
  /// **'Нысан сақталды.'**
  String get siteSaved;

  /// No description provided for @sitesTitle.
  ///
  /// In kk, this message translates to:
  /// **'Нысандар картасы'**
  String get sitesTitle;

  /// No description provided for @solarCapacity.
  ///
  /// In kk, this message translates to:
  /// **'Күн қуаты'**
  String get solarCapacity;

  /// No description provided for @solarRadiation.
  ///
  /// In kk, this message translates to:
  /// **'Күн радиациясы'**
  String get solarRadiation;

  /// No description provided for @solarTotal.
  ///
  /// In kk, this message translates to:
  /// **'Күн генерациясы'**
  String get solarTotal;

  /// No description provided for @shellBadge.
  ///
  /// In kk, this message translates to:
  /// **'ВИЭ басқаруы'**
  String get shellBadge;

  /// No description provided for @systemStatus.
  ///
  /// In kk, this message translates to:
  /// **'Жүйе күйі'**
  String get systemStatus;

  /// No description provided for @tapMapToSelect.
  ///
  /// In kk, this message translates to:
  /// **'Картадан басып координатаны таңдаңыз. Одан кейін оны жаңа нысан диалогында пайдалануға болады.'**
  String get tapMapToSelect;

  /// No description provided for @today.
  ///
  /// In kk, this message translates to:
  /// **'Бүгін'**
  String get today;

  /// No description provided for @tilt.
  ///
  /// In kk, this message translates to:
  /// **'Көлбеу бұрышы'**
  String get tilt;

  /// No description provided for @unknown.
  ///
  /// In kk, this message translates to:
  /// **'Белгісіз'**
  String get unknown;

  /// No description provided for @userRoleLabel.
  ///
  /// In kk, this message translates to:
  /// **'Smart City пайдаланушысы'**
  String get userRoleLabel;

  /// No description provided for @userOnlyWorkspace.
  ///
  /// In kk, this message translates to:
  /// **'Тек пайдаланушыға арналған жұмыс кеңістігі'**
  String get userOnlyWorkspace;

  /// No description provided for @weatherWindow.
  ///
  /// In kk, this message translates to:
  /// **'Климат терезесі'**
  String get weatherWindow;

  /// No description provided for @weatherWindowSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Open-Meteo бойынша қысқа мерзімді климаттық индикаторлар'**
  String get weatherWindowSubtitle;

  /// No description provided for @windCapacity.
  ///
  /// In kk, this message translates to:
  /// **'Жел қуаты'**
  String get windCapacity;

  /// No description provided for @windHubHeight.
  ///
  /// In kk, this message translates to:
  /// **'Хаб биіктігі'**
  String get windHubHeight;

  /// No description provided for @windSpeed.
  ///
  /// In kk, this message translates to:
  /// **'Жел жылдамдығы'**
  String get windSpeed;

  /// No description provided for @windTotal.
  ///
  /// In kk, this message translates to:
  /// **'Жел генерациясы'**
  String get windTotal;

  /// No description provided for @weatherVariant.
  ///
  /// In kk, this message translates to:
  /// **'Ауа райына арналған нұсқа'**
  String get weatherVariant;

  /// No description provided for @qualityInputs.
  ///
  /// In kk, this message translates to:
  /// **'Ауа райы деректерін бақылау'**
  String get qualityInputs;

  /// No description provided for @qualityAttention.
  ///
  /// In kk, this message translates to:
  /// **'оқыту деректерінен ауытқулар бар'**
  String get qualityAttention;

  /// No description provided for @qualityReference.
  ///
  /// In kk, this message translates to:
  /// **'тірек ауқымы шегінде'**
  String get qualityReference;

  /// No description provided for @siteEnergyEstimate.
  ///
  /// In kk, this message translates to:
  /// **'Энергия ауа райы мен қондырғы қуаты бойынша есептелген; нысан өлшемдерімен калибрленбеген.'**
  String get siteEnergyEstimate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'kk', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'kk':
      return AppLocalizationsKk();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accountSection => 'Account details';

  @override
  String get accountUid => 'User ID';

  @override
  String get activeSite => 'Active site';

  @override
  String get addSite => 'Add site';

  @override
  String get address => 'Address';

  @override
  String get appTagline =>
      'Renewable energy forecasting and load optimization platform for Smart City operations';

  @override
  String get appTitle => 'Smart City Renewable AI';

  @override
  String get authBack => 'Back';

  @override
  String get authAutoVerifyHint =>
      'Verification continues automatically after the code is fully entered.';

  @override
  String get authBenefitForecast =>
      'Professional solar and wind generation forecasts for 7 and 14 days';

  @override
  String get authBenefitMap =>
      'Map-based asset management with per-location parameter adaptation';

  @override
  String get authBenefitOptimization =>
      'Interactive load, battery, and energy balance optimization panels';

  @override
  String get authChangePhone => 'Change number';

  @override
  String get authCodeSentBadge => 'Code sent';

  @override
  String get authCodeHint => 'Enter the 6-digit SMS code';

  @override
  String get authCodeLabel => 'Verification code';

  @override
  String get authErrorSendCode => 'Unable to send the code. Please try again.';

  @override
  String get authErrorVerify => 'Code verification failed.';

  @override
  String get authHeroSubtitle =>
      'A unified digital workspace for solar and wind energy management with a focus on Astana conditions.';

  @override
  String get authHeroTitle =>
      'User workspace for precise renewable energy operations';

  @override
  String get authInvalidPhone => 'Enter a valid phone number.';

  @override
  String authOtpSubtitle(Object phone) {
    return 'Enter the verification code sent to $phone.';
  }

  @override
  String get authOtpTitle => 'Confirm sign in';

  @override
  String get authOtpSent => 'Code sent. Continue signing in.';

  @override
  String get authPhoneEntryDescription =>
      'Enter your phone number to access your workspace.';

  @override
  String get authPhoneHint => '700 000 00 00';

  @override
  String get authPhoneLabel => 'Phone number';

  @override
  String get authSendCode => 'Send code';

  @override
  String get authSmsHelper => '';

  @override
  String get authSubtitle =>
      'Sign in with a phone number. On first login, only the core profile is collected, while site parameters are added later on the map.';

  @override
  String get authTitle => 'Sign in to your workspace';

  @override
  String get authVerifyingCode => 'Verifying code';

  @override
  String get authVerify => 'Verify and continue';

  @override
  String get averageRisk => 'Model score, not a fault probability';

  @override
  String get azimuth => 'Azimuth';

  @override
  String get backupEmail => 'Backup e-mail';

  @override
  String get backToForecast => 'Back to forecast';

  @override
  String get batteryCapacity => 'Battery capacity';

  @override
  String get batteryEnabled => 'Enable battery scenario';

  @override
  String get batteryScenario => 'Battery scenario';

  @override
  String get batterySoc => 'Battery state of charge';

  @override
  String get batterySocSubtitle => 'SOC profile over time';

  @override
  String get cancel => 'Cancel';

  @override
  String get chargePower => 'Charge power';

  @override
  String get city => 'City';

  @override
  String get completeRegistration => 'Complete registration';

  @override
  String get connectedServer => 'Connected server';

  @override
  String get currentTemperature => 'Temperature';

  @override
  String get dailyBreakdown => 'Daily breakdown';

  @override
  String get dailyBreakdownSubtitle =>
      'Daily distribution of solar and wind generation';

  @override
  String get dashboardHeroSubtitle =>
      'This panel consolidates the site\'s short-term forecast, climate conditions, and overall energy system status in one place.';

  @override
  String get dashboardHeroTitle => 'Energy situation overview';

  @override
  String get dashboardSiteControlSubtitle =>
      'Select the installed site that should drive the dashboard view.';

  @override
  String get dashboardInstalledPoints => 'Installed points';

  @override
  String get dashboardDefaultSiteSaved => 'The main site has been updated.';

  @override
  String get dashboardDefaultSiteSaveError => 'Unable to update the main site.';

  @override
  String get dashboardOperationalFocusTitle => 'Operational focus';

  @override
  String get dashboardOperationalFocusSubtitle =>
      'A compact expert summary based on forecast, climate, and energy balance.';

  @override
  String get dashboardRecommendedAction => 'Recommended action';

  @override
  String get dashboardPeakWindow => 'Peak window';

  @override
  String get dashboardCoverageMode => 'Operating mode';

  @override
  String get dashboardStableMode => 'Stable renewable window';

  @override
  String get dashboardSolarMode => 'Solar-led interval';

  @override
  String get dashboardWindMode => 'Wind-supported interval';

  @override
  String get dashboardGridMode => 'Grid support required';

  @override
  String get dashboardStableAction =>
      'Shift flexible consumption toward the renewable peak and preserve battery headroom for evening hours.';

  @override
  String get dashboardSolarAction =>
      'Use the daytime production window for energy-intensive tasks and lower grid import before sunset.';

  @override
  String get dashboardWindAction =>
      'Keep dispatch balanced between wind generation and storage to smooth short-term variability.';

  @override
  String get dashboardGridAction =>
      'Prioritize critical loads and preserve battery reserve until renewable output improves.';

  @override
  String get dashboardGridDependency => 'Grid dependency';

  @override
  String get dashboardGridDependencyHint =>
      'Share of demand currently covered by external grid import';

  @override
  String get day => 'Day';

  @override
  String get day14 => '14 days';

  @override
  String get day7 => '7 days';

  @override
  String get defaultSite => 'Default site';

  @override
  String get delete => 'Delete';

  @override
  String get deleteSiteConfirm => 'Do you really want to delete this site?';

  @override
  String get dischargePower => 'Discharge power';

  @override
  String get edit => 'Edit';

  @override
  String get energyMix => 'Generation mix';

  @override
  String get extremeRisk => 'High-generation score';

  @override
  String get fetchErrorGeneric =>
      'An error occurred while loading data from the server.';

  @override
  String get forecast14Day => '14-day forecast';

  @override
  String get forecast7Day => '7-day forecast';

  @override
  String get forecastDayDetailTitle => 'Selected day profile';

  @override
  String get forecastDayDetailSubtitle =>
      'Detailed intra-day renewable generation view with 15-minute resolution.';

  @override
  String get forecastDayUnavailable =>
      'The selected day is unavailable for the active forecast range.';

  @override
  String get forecastDetailInsightTitle => 'Selected point analysis';

  @override
  String get forecastDetailInsightSubtitle =>
      'Operational reading for the fixed point on the daily chart.';

  @override
  String get forecastOpenDay => 'Open a day in detail';

  @override
  String get forecastOpenDaySubtitle =>
      'Tap a day on the chart or table to inspect the full intra-day profile.';

  @override
  String get forecastPageTitle => 'Detailed generation forecast';

  @override
  String get forecastPointRecommendation => 'Recommended action';

  @override
  String get forecastPointRisk => 'Score at this hour';

  @override
  String get forecastPointTime => 'Time';

  @override
  String get forecastRecommendationRisk =>
      'The model indicates high generation. Compare the forecast with demand and available battery capacity.';

  @override
  String get forecastRecommendationSolar =>
      'Use the strong solar interval for flexible daytime processes and battery charging.';

  @override
  String get forecastRecommendationStable =>
      'The renewable profile is balanced. Maintain normal dispatch and monitor the next transition window.';

  @override
  String get forecastRecommendationWind =>
      'Wind support is elevated. Smooth the profile with storage and avoid abrupt load ramps.';

  @override
  String get forecastTable => 'Daily table';

  @override
  String get forecastTableSubtitle =>
      'Aggregated values and day-level structure';

  @override
  String get forecastTapDayHint =>
      'Selecting a day opens a detailed profile page.';

  @override
  String get fullName => 'Full name';

  @override
  String get goToSites => 'Go to sites';

  @override
  String get gridImportAfter => 'Grid import after';

  @override
  String get gridImportBefore => 'Grid import before';

  @override
  String get healthStatus => 'Service status';

  @override
  String get hourlyCurve => 'Hourly curve';

  @override
  String get hourlyCurveSubtitle =>
      'Solar, wind, and total generation for the next 72 hours';

  @override
  String get humidity => 'Humidity';

  @override
  String get initialCharge => 'Initial charge';

  @override
  String get initialSiteNameDefault => 'Astana main site';

  @override
  String get invalidEmail => 'Invalid e-mail format.';

  @override
  String get invalidNumber => 'Enter a numeric value.';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageKazakh => 'Kazakh';

  @override
  String get languageRussian => 'Russian';

  @override
  String get languageShortEnglish => 'ENG';

  @override
  String get languageShortKazakh => 'KAZ';

  @override
  String get languageShortRussian => 'RUS';

  @override
  String get latitude => 'Latitude';

  @override
  String get lastUpdatedLabel => 'Last update';

  @override
  String get loadFailed => 'Loading failed';

  @override
  String get loadDemand => 'Load';

  @override
  String get loadVsRenewable => 'Load and generation';

  @override
  String get loadVsRenewableSubtitle =>
      'Comparison of load, renewables, and grid import';

  @override
  String get localeSection => 'Language and preferences';

  @override
  String get longitude => 'Longitude';

  @override
  String get mapLegend => 'Clicking on the map selects a new coordinate';

  @override
  String get mapAnalyticsTitle => 'Forecast explorer';

  @override
  String get mapAnalyticsSubtitle =>
      'Switch between today, 7-day, and 14-day views. Tap a bar to open the detailed daily profile.';

  @override
  String get mapDraftPointTitle => 'New point ready to add';

  @override
  String get mapDraftPointSubtitle =>
      'Review the coordinates and open the site form to register equipment at this location.';

  @override
  String get mapTapBarHint =>
      'Tap any bar to open the detailed daily forecast page.';

  @override
  String get maxCharge => 'Max charge';

  @override
  String get minCharge => 'Min charge';

  @override
  String get modelVersion => 'Model version';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navForecast => 'Forecast';

  @override
  String get navOptimization => 'Optimization';

  @override
  String get navProfile => 'Profile';

  @override
  String get navSites => 'Sites';

  @override
  String get netLoad => 'Net load';

  @override
  String get next72Hours => 'Next 72 hours';

  @override
  String get next72HoursSubtitle =>
      'Short-term comparison between load and generation';

  @override
  String get noSiteMessage =>
      'Add an energy site first. It is required for maps, forecasting, and optimization.';

  @override
  String get noSiteTitle => 'No site yet';

  @override
  String get noSitesYet => 'No sites yet';

  @override
  String get noSitesYetMessage =>
      'Add the first solar or wind site and immediately start server-side forecasts.';

  @override
  String get notes => 'Notes';

  @override
  String get onboardingDefaultSiteHint =>
      'After registration, add a point on the map and enter the forecasting parameters there.';

  @override
  String get onboardingProfileSection => 'User profile';

  @override
  String get onboardingSaveError => 'Failed to save the profile.';

  @override
  String get onboardingSiteSection => 'Initial energy site';

  @override
  String get onboardingSubtitle =>
      'Start with the essential user profile only. Geolocation, capacities, and forecasting point parameters will be added later on the map.';

  @override
  String get onboardingSuccess =>
      'Profile saved successfully. Next step: add a site on the map.';

  @override
  String get onboardingTitle => 'Initial setup';

  @override
  String get optimizationMethodSubtitle =>
      'Scenario parameters are passed to the lexicographic dispatch model.';

  @override
  String get optimizationGuideTitle => 'How to work with this page';

  @override
  String get optimizationGuideSubtitle =>
      'Follow the sequence below so battery settings and optimization results stay clear on both desktop and mobile.';

  @override
  String get optimizationGuideConfigureTitle => 'Configure the battery window';

  @override
  String get optimizationGuideConfigureBody =>
      'Set capacity, charge and discharge power, and the allowed reserve band before launching the scenario.';

  @override
  String get optimizationGuideRunTitle => 'Run the scenario';

  @override
  String get optimizationGuideRunBody =>
      'Start optimization after adjusting the sliders to refresh load, import, and SOC projections for the selected horizon.';

  @override
  String get optimizationGuideReviewTitle => 'Review the effect';

  @override
  String get optimizationGuideReviewBody =>
      'Compare grid import before and after, then inspect the load curve and battery SOC to decide whether the settings are practical.';

  @override
  String get optimizationReserveBand => 'Reserve band';

  @override
  String get optimizationSubtitle =>
      'Reduce grid import based on site load, renewables, and battery behavior';

  @override
  String get optimizationTitle => 'Load optimization';

  @override
  String get openFullscreenMap => 'Open full-screen map';

  @override
  String get organization => 'Organization name';

  @override
  String get peakRenewable => 'Peak generation';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get preferredLanguage => 'Preferred language';

  @override
  String get profileSaveError => 'Unable to update the profile.';

  @override
  String get profileSaved => 'Profile updated.';

  @override
  String get profileSubtitle =>
      'User settings, language, and server connectivity status';

  @override
  String get profileTitle => 'Profile';

  @override
  String get reduction => 'Reduction';

  @override
  String get refresh => 'Refresh';

  @override
  String get refreshForecast => 'Refresh forecast';

  @override
  String get renewable => 'Renewables';

  @override
  String get renewableTotal => 'Total renewable output';

  @override
  String get requiredField => 'This field is required.';

  @override
  String get retry => 'Retry';

  @override
  String get runOptimization => 'Run optimization';

  @override
  String get save => 'Save';

  @override
  String get saveSite => 'Save site';

  @override
  String get selectedSite => 'Selected site';

  @override
  String get selfSufficiency => 'Self-sufficiency';

  @override
  String get serverModel => 'Server model';

  @override
  String get setAsDefault => 'Set as default';

  @override
  String get shellSubtitle =>
      'Monitor generation, load, and energy resilience for Smart City in one workspace';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutConfirmTitle => 'Confirm sign out';

  @override
  String get signOutConfirmMessage =>
      'The current session will be closed on this device. You will need to sign in again with your phone number.';

  @override
  String get signOutConfirmAction => 'Sign out of account';

  @override
  String get signOutStay => 'Stay signed in';

  @override
  String get signedInPhone => 'Signed-in phone';

  @override
  String get siteDeleted => 'Site deleted.';

  @override
  String get closeFullscreenMap => 'Close full-screen map';

  @override
  String get siteFormTitleEdit => 'Edit site';

  @override
  String get siteFormTitleNew => 'New site';

  @override
  String get siteList => 'Site list';

  @override
  String get siteListSubtitle => 'Solar, wind, and battery parameters';

  @override
  String get siteName => 'Site name';

  @override
  String get sitePreferences => 'Default site and language';

  @override
  String get siteSaved => 'Site saved.';

  @override
  String get sitesTitle => 'Site map';

  @override
  String get solarCapacity => 'Solar capacity';

  @override
  String get solarRadiation => 'Solar radiation';

  @override
  String get solarTotal => 'Solar generation';

  @override
  String get shellBadge => 'Renewable control';

  @override
  String get systemStatus => 'System status';

  @override
  String get tapMapToSelect =>
      'Click on the map to select a coordinate. You can then reuse it in the new site dialog.';

  @override
  String get today => 'Today';

  @override
  String get tilt => 'Tilt angle';

  @override
  String get unknown => 'Unknown';

  @override
  String get userRoleLabel => 'Smart City user';

  @override
  String get userOnlyWorkspace => 'User-only workspace';

  @override
  String get weatherWindow => 'Climate window';

  @override
  String get weatherWindowSubtitle =>
      'Short-term climate indicators from Open-Meteo';

  @override
  String get windCapacity => 'Wind capacity';

  @override
  String get windHubHeight => 'Hub height';

  @override
  String get windSpeed => 'Wind speed';

  @override
  String get windTotal => 'Wind generation';

  @override
  String get weatherVariant => 'Weather variant';

  @override
  String get qualityInputs => 'Weather quality';

  @override
  String get qualityAttention => 'deviations from training reference';

  @override
  String get qualityReference => 'within reference range';

  @override
  String get siteEnergyEstimate =>
      'Energy estimated from weather and installed capacity; not calibrated against site measurements.';
}

//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.singletons
import qs.tests

// Run with: tests/run-unit.sh (in private headless compositors: several suites open a window).
// Each suite registers here once, one `property var _name: SomethingTest {}` line, and
// nowhere else: tests/run-unit.sh reads the suites from these lines (tests/count-suites.sh),
// splits them into shards — each a Quickshell process of its own running this file with only
// its suites selected (TestCase.selected) — and the asynchronous ones are found below by
// what they are. No suite waits for another: each builds its own state, and a suite that
// changes what is shared in a process with others says so (TestCase.ownProcess).
QtObject {
    id: root

    // First, before any suite runs: the suites use the real Config singleton, whose
    // file is the user's
    readonly property bool _configReadOnly: { Config.readOnly = true; return true; }
    // First too: no reload when a file of the tree changes (Quickshell watches the files it
    // loaded by default). A reload in the middle of a run starts every suite again in a new
    // generation while the old one's timers still fire: a shard reports its suites twice or
    // crashes, whenever the tree is edited while the tests run.
    readonly property bool _noReload: { Quickshell.watchFiles = false; return true; }
    // Each suite that shares its process leaves the shared state as it found it, or fails
    // (SharedState, TestCase): the check reads it with this
    readonly property QtObject _stateReader: SharedStateReader {}
    readonly property bool _stateChecked: { SharedState.reader = root._stateReader; SharedState.checking = root._stateReader !== null; return true; }
    // Animations instant, so suites do not wait on them, unless a suite selected here tests
    // one (TestCase.animations). Set with the bindings, before any suite runs; in an object
    // of its own, as listing this object's properties for _suites reads them all.
    readonly property QtObject _motion: QtObject {
        readonly property bool instant: {
            const instant = !root._suites.some(suite => suite.selected && suite.animations);
            Theme.instantAnimations = instant;
            return instant;
        }
    }

    property var _promises: PromisesTest {}
    property var _teardown: TeardownTest {}
    property var _fetch: FetchTest {}
    property var _network: NetworkTest {}
    property var _deviceAddressReading: DeviceAddressReadingTest {}
    property var _sleepLockStateReading: SleepLockStateReadingTest {}
    property var _vpnProviders: VpnProvidersTest {}
    property var _calendarDates: CalendarDatesTest {}
    property var _calendarEvents: CalendarEventsTest {}
    property var _widgetRegistry: WidgetRegistryTest {}
    property var _widgetPresets: WidgetPresetsTest {}
    property var _widgetActions: WidgetActionsTest {}
    property var _coreActionRules: CoreActionRulesTest {}
    property var _hardware: HardwareTest {}
    property var _profiles: ProfilesTest {}
    property var _polling: PollingTest {}
    property var _settingsPages: SettingsPagesTest {}
    property var _workspaces: WorkspacesTest {}
    property var _version: VersionTest {}
    property var _theme: ThemeTest {}
    property var _themeMaps: ThemeMapsTest {}
    property var _themeBackups: ThemeBackupsTest {}
    property var _apiThemeTokens: ApiThemeTokensTest {}
    property var _format: FormatTest {}
    property var _addressRules: AddressRulesTest {}
    property var _systemFacts: SystemFactsTest {}
    property var _distributionRules: DistributionRulesTest {}
    property var _distributionReading: DistributionReadingTest {}
    property var _distributionUnknown: DistributionUnknownTest {}
    property var _etcFilesRules: EtcFilesRulesTest {}
    property var _nixosConfigRules: NixosConfigRulesTest {}
    property var _nixosConfigurationReading: NixosConfigurationReadingTest {}
    property var _nixBuildRules: NixBuildRulesTest {}
    property var _nixosApplyRules: NixosApplyRulesTest {}
    property var _nixosApplyLive: NixosApplyLiveTest {}
    property var _nixosApplyScript: NixosApplyScriptTest {}
    property var _nixosRebuildRules: NixosRebuildRulesTest {}
    property var _nixosViewRules: NixosViewRulesTest {}
    property var _nixosRebuildViewRules: NixosRebuildViewRulesTest {}
    property var _nixosRebuildPanel: NixosRebuildPanelTest {}
    property var _nixosPage: NixosPageTest {}
    property var _nixosDeclare: NixosDeclareTest {}
    property var _etcFiles: EtcFilesTest {}
    property var _integrationChange: IntegrationChangeTest {}
    property var _distributionContract: DistributionContractTest {}
    property var _integrationRules: IntegrationRulesTest {}
    property var _notifier: NotifierTest {}
    property var _scrollNotches: ScrollNotchesTest {}
    property var _curvePoints: CurvePointsTest {}
    property var _notificationMarkup: NotificationMarkupTest {}
    property var _roundedOutline: RoundedOutlineTest {}
    property var _cavaRules: CavaRulesTest {}
    property var _cavaReading: CavaReadingTest {}
    property var _coverColors: CoverColorsTest {}
    property var _playerRules: PlayerRulesTest {}
    property var _barText: BarTextTest {}
    property var _barGeometry: BarGeometryTest {}
    property var _pointerRules: PointerRulesTest {}
    property var _interactionRules: InteractionRulesTest {}
    property var _batteryRules: BatteryRulesTest {}
    property var _toastRules: ToastRulesTest {}
    property var _notificationRules: NotificationRulesTest {}
    property var _wallpaperRules: WallpaperRulesTest {}
    property var _polkitRules: PolkitRulesTest {}
    property var _privilegedRules: PrivilegedRulesTest {}
    property var _energyRules: EnergyRulesTest {}
    property var _lockRules: LockRulesTest {}
    property var _lockParseRules: LockParseRulesTest {}
    property var _lockViewRules: LockViewRulesTest {}
    property var _lockRecoveryRules: LockRecoveryRulesTest {}
    property var _lockIoRules: LockIoRulesTest {}
    property var _testSeamRules: TestSeamRulesTest {}
    property var _testSeamsShape: TestSeamsShapeTest {}
    property var _lockscreenShape: LockscreenShapeTest {}
    property var _testTree: TestTreeTest {}
    property var _pointerInput: PointerInputTest {}
    property var _buttonKinds: ButtonKindsTest {}
    property var _buttonKeys: ButtonKeysTest {}
    property var _toastDrag: ToastDragTest {}
    property var _pillSizes: PillSizesTest {}
    property var _apiElements: ApiElementsTest {}
    property var _sidePanel: SidePanelTest {}
    property var _settingsModal: SettingsModalTest {}
    property var _statusPill: StatusPillTest {}
    property var _modulesPage: ModulesPageTest {}
    property var _hud: HudTest {}
    property var _lockView: LockViewTest {}
    property var _authPromptView: AuthPromptViewTest {}
    property var _moduleRules: ModuleRulesTest {}
    property var _apiLists: ApiListsTest {}
    property var _moduleInstallRules: ModuleInstallRulesTest {}
    property var _fileChooserRules: FileChooserRulesTest {}
    property var _fileChooser: FileChooserTest {}
    property var _commandRules: CommandRulesTest {}
    property var _commandRunner: CommandRunnerTest {}
    property var _listKeyRules: ListKeyRulesTest {}
    property var _readOnlyRules: ReadOnlyRulesTest {}
    property var _migrationRules: MigrationRulesTest {}
    property var _moduleMigrationRules: ModuleMigrationRulesTest {}
    property var _migrations: MigrationsTest {}
    property var _migrationsGolden: MigrationsGoldenTest {}
    property var _configFile: ConfigFileTest {}
    property var _configMigration: ConfigMigrationTest {}
    property var _migrationNoticeRules: MigrationNoticeRulesTest {}
    property var _migrationRestore: MigrationRestoreTest {}
    property var _migrationFailureEntry: MigrationFailureEntryTest {}
    property var _configBackupRules: ConfigBackupRulesTest {}
    property var _configBackups: ConfigBackupsTest {}
    property var _backupsSettings: BackupsSettingsTest {}
    property var _devRules: DevRulesTest {}
    property var _moduleDependencyRules: ModuleDependencyRulesTest {}
    property var _moduleUpdateRules: ModuleUpdateRulesTest {}
    property var _moduleBackupRules: ModuleBackupRulesTest {}
    property var _moduleWaitingRules: ModuleWaitingRulesTest {}
    property var _keyedViews: KeyedViewsTest {}
    property var _settingsCard: SettingsCardTest {}
    property var _floatingList: FloatingListTest {}
    property var _moduleContribution: ModuleContributionTest {}
    property var _networkCardGeometry: NetworkCardGeometryTest {}
    property var _quickshellPin: QuickshellPinTest {}
    property var _modules: ModulesTest {}
    property var _moduleIcon: ModuleIconTest {}
    property var _moduleRegistries: ModuleRegistriesTest {}
    property var _anchors: AnchorsTest {}
    property var _moduleInstaller: ModuleInstallerTest {}
    property var _moduleUpdater: ModuleUpdaterTest {}
    property var _moduleWaitingNotice: ModuleWaitingNoticeTest {}
    property var _moduleBackup: ModuleBackupTest {}
    property var _moduleMigrations: ModuleMigrationsTest {}
    property var _idleRules: IdleRulesTest {}
    property var _awayViewRules: AwayViewRulesTest {}
    property var _sleepNoticeRules: SleepNoticeRulesTest {}
    property var _hibernateRules: HibernateRulesTest {}
    property var _connectivityRules: ConnectivityRulesTest {}
    property var _nmConfigFiles: NmConfigFilesTest {}
    property var _monitorRules: MonitorRulesTest {}
    property var _screenPowerReading: ScreenPowerReadingTest {}
    property var _wlopmScreenPowerReading: WlopmScreenPowerReadingTest {}
    property var _logindIdleBlockReading: LogindIdleBlockReadingTest {}
    property var _logindSleepReading: LogindSleepReadingTest {}
    property var _pamStackRules: PamStackRulesTest {}
    property var _pamStacksReading: PamStacksReadingTest {}
    property var _helper: HelperTest {}
    property var _pamRuleRules: PamRuleRulesTest {}
    property var _pamEditRules: PamEditRulesTest {}
    property var _pamTrialRules: PamTrialRulesTest {}
    property var _pamTrial: PamTrialTest {}
    property var _pamNixosModule: PamNixosModuleTest {}
    property var _pamApplyRules: PamApplyRulesTest {}
    property var _rememberRules: RememberRulesTest {}
    property var _rememberNixosModule: RememberNixosModuleTest {}
    property var _rememberedAdminReading: RememberedAdminReadingTest {}
    property var _rememberInstallRules: RememberInstallRulesTest {}
    property var _rememberInstall: RememberInstallTest {}
    property var _vpnLockdownInstallRules: VpnLockdownInstallRulesTest {}
    property var _vpnLockdownInstall: VpnLockdownInstallTest {}
    property var _rememberAdminPage: RememberAdminPageTest {}
    property var _pamApply: PamApplyTest {}
    property var _pamRuleList: PamRuleListTest {}
    property var _pamRulesPage: PamRulesPageTest {}
    property var _pageShown: PageShownTest {}
    property var _glyphs: GlyphsTest {}
    // A new suite: its one line above this comment

    // Every suite registered above, read from this object's own properties, and those of them
    // that run on the event loop (TestCase.asynchronous)
    readonly property var _suites: Object.keys(root).filter(key => /^_[A-Za-z0-9]+$/.test(key))
                                                   .map(key => root[key])
                                                   .filter(value => value !== null && typeof value === "object" && typeof value.suiteName === "string"
                                                                    && typeof value.runAsync === "function")
    readonly property var _asyncSuites: _suites.filter(suite => suite.asynchronous)
    // How long an asynchronous suite may take, unless it sets its own (TestCase.timeLimitMs);
    // then it fails as timed out. Counted from the start of the suites.
    readonly property int _asyncLimitMs: 90000
    // No suite runs past this, counted from the start of the suites. It stays under
    // tests/headless.sh's limit on Quickshell (`timeout 480`, labwc's 540), so that a run that
    // hangs ends here, naming its suites, not killed from outside.
    readonly property int _runLimitMs: 420000
    function timeLimitOf(suite) {
        return Math.min(suite.timeLimitMs > 0 ? suite.timeLimitMs : _asyncLimitMs, _runLimitMs);
    }

    // Exit once the synchronous suites have run (all in Component.onCompleted) and the
    // asynchronous ones are done — each failed as timed out once past its own limit. A suite
    // that was not selected is done from the start.
    property var _quit: Timer {
        interval: 50
        running: true
        repeat: true
        property int _waited: 0
        onTriggered: {
            _waited += interval;
            for (const suite of root._asyncSuites) {
                // Finished, its verdict waiting for the state to settle (TestCase.finish)
                if (suite.done || suite._finished)
                    continue;
                const limit = root.timeLimitOf(suite);
                if (_waited >= limit) {
                    suite.fail("timed out (" + Math.round(limit / 1000) + " s)");
                    suite.finish();
                }
            }
            if (root._asyncSuites.every(suite => suite.done))
                Qt.quit();
        }
    }
}

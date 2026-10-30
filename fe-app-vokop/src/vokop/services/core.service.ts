import { TabServiceInstance } from './tab.service';
import { store } from './store.service';
import { logger } from './logger.service';
import { VokopLogWatcher } from './vokopLogWatcher.service';
import {
  getVokopLogNotification,
  LogNotificationDeduper,
  VokopLogNotification,
} from './logNotificationDeduper.service';
import { VokopShellMethods } from '../methods';
import {
  registerRuntimeStateResumeRefresh,
  startRuntimeUiStatePolling,
} from './runtimeUiState.service';

type CoreServiceOptions = {
  waitForLogWatcherStart?: () => Promise<unknown>;
  logWatcherStartDelayMs?: number;
};

const LOG_WATCHER_INTERVAL_MS = 10000;
const LOG_WATCHER_START_DELAY_MS = 5000;

function componentDisplayName(component: string) {
  const names: Record<string, string> = {
    vokop: 'Vokop',
    sing_box: 'sing-box',
    zapret: 'Zapret',
    zapret2: 'Zapret2',
    byedpi: 'ByeDPI',
  };

  return names[component] || component;
}

function showLogNotification(notification: VokopLogNotification) {
  if (notification.kind === 'component-update') {
    const message = _('New version %s is available for %s')
      .replace('%s', notification.version)
      .replace('%s', componentDisplayName(notification.component));

    ui.addNotification(
      _('Component update available'),
      E('div', {}, message),
      'warning',
      'fkp-component-update-notification',
    );
    return;
  }

  ui.addNotification(
    _('Vokop Error'),
    E('div', {}, notification.line),
    'error',
    'fkp-log-error-notification',
  );
}

export function coreService(options: CoreServiceOptions = {}) {
  TabServiceInstance.onChange((activeId, tabs) => {
    logger.info('[TAB]', activeId);
    store.set({
      tabService: {
        current: activeId || '',
        all: tabs.map((tab) => tab.id),
      },
    });
  });

  const watcher = VokopLogWatcher.getInstance();
  const logNotificationDeduper = new LogNotificationDeduper();

  watcher.init(
    async () => {
      const logs = await VokopShellMethods.checkLogs();

      if (logs.success) {
        return logs.data as string;
      }

      return '';
    },
    {
      intervalMs: LOG_WATCHER_INTERVAL_MS,
      onNewLog: (line) => {
        if (logNotificationDeduper.shouldNotify(line)) {
          const notification = getVokopLogNotification(line);
          if (notification) {
            showLogNotification(notification);
          }
        }
      },
    },
  );

  const startWatcher = async () => {
    if (options.waitForLogWatcherStart) {
      await Promise.resolve()
        .then(() => options.waitForLogWatcherStart?.())
        .catch(() => null);
    }

    watcher.start();
  };
  const scheduleStartWatcher = () =>
    window.setTimeout(() => {
      void startWatcher();
    }, options.logWatcherStartDelayMs ?? LOG_WATCHER_START_DELAY_MS);

  if (typeof window !== 'undefined') {
    scheduleStartWatcher();
  } else {
    void startWatcher();
  }

  registerRuntimeStateResumeRefresh();
  startRuntimeUiStatePolling();
}

import { VokopShellMethods } from '../methods';
import { logger } from '../services/logger.service';
import { store } from '../services/store.service';
import { refreshRuntimeUiState } from '../services/runtimeUiState.service';
import { Vokop } from '../types';

let latestServicesInfoRequestId = 0;

function getSettledMethodResponse<T>(
  scope: string,
  result: PromiseSettledResult<Vokop.MethodResponse<T>>,
): Vokop.MethodResponse<T> {
  if (result.status === 'fulfilled') {
    return result.value;
  }

  logger.error('[SERVICES_INFO]', `${scope} failed`, result.reason);

  return {
    success: false,
    error: result.reason instanceof Error ? result.reason.message : '',
  };
}

export async function fetchServicesInfo() {
  const requestId = ++latestServicesInfoRequestId;
  const uiState = await refreshRuntimeUiState({ force: true });

  if (requestId !== latestServicesInfoRequestId) {
    return;
  }

  if (uiState) {
    return uiState;
  }

  const [vokopResult, singboxResult] = await Promise.allSettled([
    VokopShellMethods.getStatus(),
    VokopShellMethods.getSingBoxStatus(),
  ]);

  if (requestId !== latestServicesInfoRequestId) {
    return;
  }

  const vokop = getSettledMethodResponse('getStatus', vokopResult);
  const singbox = getSettledMethodResponse('getSingBoxStatus', singboxResult);
  const previousData = store.get().servicesInfoWidget.data;

  store.set({
    servicesInfoWidget: {
      loading: false,
      failed: !vokop.success || !singbox.success,
      data: {
        singbox: singbox.success ? singbox.data.running : previousData.singbox,
        vokopRunning: vokop.success
          ? vokop.data.running
          : previousData.vokopRunning,
        vokopEnabled: vokop.success
          ? vokop.data.enabled
          : previousData.vokopEnabled,
        vokopStatus: vokop.success
          ? vokop.data.status
          : previousData.vokopStatus,
      },
    },
  });

  return undefined;
}

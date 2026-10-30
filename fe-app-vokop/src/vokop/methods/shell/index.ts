import { callBaseMethod } from './callBaseMethod';
import { ClashAPI, Vokop } from '../../types';
import { executeShellCommand } from '../../../helpers';
import { isTransientRpcError } from '../../helpers/isTransientRpcError';

const SUBSCRIPTION_UPDATE_RPC_TIMEOUT_MS = 15000;
const SUBSCRIPTION_UPDATE_POLL_INTERVAL_MS = 1500;
const UI_ACTION_RPC_TIMEOUT_MS = 15000;
const UI_ACTION_TRANSIENT_RPC_GRACE_MS = 30000;
const SERVICE_ACTION_TIMEOUT_MS = 2 * 60 * 1000;
const SERVICE_ACTION_POLL_INTERVAL_MS = 1000;
const LATENCY_TEST_TIMEOUT_MS = 30 * 1000;
const LATENCY_TEST_POLL_INTERVAL_MS = 1000;
const COMPONENT_ACTION_RPC_TIMEOUT_MS = 15000;
const COMPONENT_ACTION_POLL_INTERVAL_MS = 1500;
const COMPONENT_ACTION_STATUS_REFRESH_INTERVAL_MS = 15000;
const COMPONENT_ACTION_SELF_UPDATE_SETTLE_MS = 30000;
const COMPONENT_ACTION_TRANSIENT_RPC_GRACE_MS = 30000;
const COMPONENT_ACTION_STATE_DIR = '/var/run/vokop/component-actions';
const GET_UI_STATE_RPC_TIMEOUT_MS = 3000;

function sleep(ms: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

function translate(message: string) {
  return typeof _ === 'function' ? _(message) : message;
}

function parseJsonObjectOutput<T>(output: string): T | null {
  if (!output) {
    return null;
  }

  try {
    return JSON.parse(output) as T;
  } catch (_error) {
    const jsonMatch = output.match(/(\{[\s\S]*\})\s*$/);

    if (!jsonMatch) {
      return null;
    }

    try {
      return JSON.parse(jsonMatch[1]) as T;
    } catch (_jsonError) {
      return null;
    }
  }
}

function parseComponentActionOutput(output: string) {
  return parseJsonObjectOutput<Vokop.ComponentActionResult>(output);
}

function parseComponentActionResult(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
) {
  return parseComponentActionOutput(response.stdout);
}

function parseComponentActionStartResult(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
) {
  const parsedResponse = parseComponentActionResult(response);

  if (!parsedResponse) {
    return null;
  }

  return parsedResponse as unknown as Vokop.ComponentActionStartResult;
}

function parseSubscriptionUpdateStartResult(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
) {
  return parseJsonObjectOutput<Vokop.SubscriptionUpdateStartResult>(
    response.stdout,
  );
}

function parseSubscriptionUpdateJobState(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
) {
  return parseJsonObjectOutput<Vokop.SubscriptionUpdateJobState>(
    response.stdout,
  );
}

function parseUiActionStartResult(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
) {
  return parseJsonObjectOutput<Vokop.UiActionStartResult>(response.stdout);
}

function parseServiceActionState(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
) {
  return parseJsonObjectOutput<Vokop.ServiceActionState>(response.stdout);
}

function parseLatencyActionState(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
) {
  return parseJsonObjectOutput<Vokop.LatencyActionState>(response.stdout);
}

function isComponentActionJobId(jobId: string) {
  return /^[A-Za-z0-9._-]+$/.test(jobId) && jobId !== '.' && jobId !== '..';
}

async function readComponentActionState(jobId: string) {
  if (!isComponentActionJobId(jobId)) {
    return null;
  }

  try {
    return parseComponentActionOutput(
      await fs.read(`${COMPONENT_ACTION_STATE_DIR}/${jobId}.json`),
    );
  } catch (_error) {
    return null;
  }
}

async function readVokopVersion() {
  const response = await executeShellCommand({
    command: '/usr/bin/vokop',
    args: ['show_version'],
    timeout: COMPONENT_ACTION_RPC_TIMEOUT_MS,
  });

  if ((response.code ?? 0) !== 0 || !response.stdout) {
    return '';
  }

  return response.stdout.trim();
}

async function isComponentActionStillRunning(
  jobId: string,
  component: Vokop.ComponentName,
  action: Vokop.ComponentAction,
) {
  const response = await callBaseMethod<Vokop.UiState>(
    Vokop.AvailableMethods.GET_UI_STATE,
    [],
    '/usr/bin/vokop',
    { timeout: GET_UI_STATE_RPC_TIMEOUT_MS },
  );

  return (
    response.success &&
    response.data.actions.component.some(
      (state) =>
        state.job_id === jobId &&
        state.component === component &&
        state.action === action &&
        state.running === true,
    )
  );
}

function componentActionFailure(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
  parsedResponse?: Pick<Vokop.ComponentActionResult, 'message'> | null,
) {
  return {
    success: false,
    error: parsedResponse?.message || response.stderr || _('Failed to execute'),
  } as Vokop.MethodFailureResponse;
}

function uiActionFailure(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
  parsedResponse?: { message?: string } | null,
  fallback: string = _('Failed to execute'),
) {
  return {
    success: false,
    error: parsedResponse?.message || response.stderr || fallback,
  } as Vokop.MethodFailureResponse;
}

function createTransientRpcGraceTracker(graceMs: number) {
  let failureStartedAt = 0;

  return {
    reset() {
      failureStartedAt = 0;
    },
    shouldContinue(error?: string) {
      if (!isTransientRpcError(error)) {
        failureStartedAt = 0;
        return false;
      }

      if (!failureStartedAt) {
        failureStartedAt = Date.now();
      }

      return Date.now() - failureStartedAt < graceMs;
    },
  };
}

export const VokopShellMethods = {
  checkDNSAvailable: async () =>
    callBaseMethod<Vokop.DnsCheckResult>(
      Vokop.AvailableMethods.CHECK_DNS_AVAILABLE,
    ),
  checkFakeIP: async () =>
    callBaseMethod<Vokop.FakeIPCheckResult>(
      Vokop.AvailableMethods.CHECK_FAKEIP,
    ),
  checkNftRules: async () =>
    callBaseMethod<Vokop.NftRulesCheckResult>(
      Vokop.AvailableMethods.CHECK_NFT_RULES,
    ),
  checkZapretRuntime: async () =>
    callBaseMethod<Vokop.ZapretCheckResult>(
      Vokop.AvailableMethods.CHECK_ZAPRET_RUNTIME,
    ),
  checkZapret2Runtime: async () =>
    callBaseMethod<Vokop.Zapret2CheckResult>(
      Vokop.AvailableMethods.CHECK_ZAPRET2_RUNTIME,
    ),
  checkByedpiRuntime: async () =>
    callBaseMethod<Vokop.ByedpiCheckResult>(
      Vokop.AvailableMethods.CHECK_BYEDPI_RUNTIME,
    ),
  checkInboundsConfig: async () =>
    callBaseMethod<Vokop.InboundsConfigCheckResult>(
      Vokop.AvailableMethods.CHECK_INBOUNDS_CONFIG,
    ),
  getStatus: async () =>
    callBaseMethod<Vokop.GetStatus>(Vokop.AvailableMethods.GET_STATUS),
  getOutboundMetadata: async (section: string) =>
    callBaseMethod<Vokop.GetOutboundMetadata>(
      Vokop.AvailableMethods.GET_OUTBOUND_METADATA,
      [section],
    ),
  getSubscriptionMetadata: async (section: string) =>
    callBaseMethod<Vokop.SubscriptionMetadata | Vokop.SubscriptionMetadata[]>(
      Vokop.AvailableMethods.GET_SUBSCRIPTION_METADATA,
      [section],
    ),
  checkSingBox: async () =>
    callBaseMethod<Vokop.SingBoxCheckResult>(
      Vokop.AvailableMethods.CHECK_SING_BOX,
    ),
  checkInbounds: async () =>
    callBaseMethod<Vokop.InboundsCheckResult>(
      Vokop.AvailableMethods.CHECK_INBOUNDS,
    ),
  getSingBoxStatus: async () =>
    callBaseMethod<Vokop.GetSingBoxStatus>(
      Vokop.AvailableMethods.GET_SING_BOX_STATUS,
    ),
  getZapretStatus: async () =>
    callBaseMethod<Vokop.GetZapretStatus>(
      Vokop.AvailableMethods.GET_ZAPRET_STATUS,
    ),
  getZapret2Status: async () =>
    callBaseMethod<Vokop.GetZapret2Status>(
      Vokop.AvailableMethods.GET_ZAPRET2_STATUS,
    ),
  getByedpiStatus: async () =>
    callBaseMethod<Vokop.GetByedpiStatus>(
      Vokop.AvailableMethods.GET_BYEDPI_STATUS,
    ),
  getClashApiProxies: async () =>
    callBaseMethod<ClashAPI.Proxies>(Vokop.AvailableMethods.CLASH_API, [
      Vokop.AvailableClashAPIMethods.GET_PROXIES,
    ]),
  getClashApiConnections: async () =>
    callBaseMethod<unknown>(Vokop.AvailableMethods.CLASH_API, [
      Vokop.AvailableClashAPIMethods.GET_CONNECTIONS,
    ]),
  getClashApiProxyLatency: async (tag: string, timeout = '5000') =>
    callBaseMethod<Vokop.GetClashApiProxyLatency>(
      Vokop.AvailableMethods.CLASH_API,
      [Vokop.AvailableClashAPIMethods.GET_PROXY_LATENCY, tag, timeout],
    ),
  getClashApiProxyLatencies: async (tags: string[]) =>
    callBaseMethod<Vokop.GetClashApiProxyLatencies>(
      Vokop.AvailableMethods.CLASH_API,
      [
        Vokop.AvailableClashAPIMethods.GET_PROXY_LATENCIES,
        JSON.stringify(tags),
        '5000',
      ],
    ),
  getClashApiGroupLatency: async (tag: string) =>
    callBaseMethod<Vokop.GetClashApiGroupLatency>(
      Vokop.AvailableMethods.CLASH_API,
      [Vokop.AvailableClashAPIMethods.GET_GROUP_LATENCY, tag, '10000'],
    ),
  setClashApiGroupProxy: async (group: string, proxy: string) =>
    callBaseMethod<unknown>(Vokop.AvailableMethods.CLASH_API, [
      Vokop.AvailableClashAPIMethods.SET_GROUP_PROXY,
      group,
      proxy,
    ]),
  closeClashApiConnection: async (connectionId: string) =>
    callBaseMethod<unknown>(Vokop.AvailableMethods.CLASH_API, [
      Vokop.AvailableClashAPIMethods.CLOSE_CONNECTION,
      connectionId,
    ]),
  closeAllClashApiConnections: async () =>
    callBaseMethod<unknown>(Vokop.AvailableMethods.CLASH_API, [
      Vokop.AvailableClashAPIMethods.CLOSE_ALL_CONNECTIONS,
    ]),
  enable: async () =>
    callBaseMethod<unknown>(
      Vokop.AvailableMethods.ENABLE,
      [],
      '/etc/init.d/vokop',
    ),
  disable: async () =>
    callBaseMethod<unknown>(
      Vokop.AvailableMethods.DISABLE,
      [],
      '/etc/init.d/vokop',
    ),
  globalCheck: async (masked = true) =>
    callBaseMethod<unknown>(Vokop.AvailableMethods.GLOBAL_CHECK, [
      masked ? 'masked' : 'raw',
    ]),
  showSingBoxConfig: async (masked = true) =>
    callBaseMethod<unknown>(Vokop.AvailableMethods.SHOW_SING_BOX_CONFIG, [
      masked ? 'masked' : 'raw',
    ]),
  checkLogs: async () =>
    callBaseMethod<unknown>(Vokop.AvailableMethods.CHECK_LOGS),
  checkSingBoxLogs: async () =>
    callBaseMethod<unknown>(Vokop.AvailableMethods.CHECK_SING_BOX_LOGS),
  getSystemInfo: async () =>
    callBaseMethod<Vokop.GetSystemInfo>(
      Vokop.AvailableMethods.GET_SYSTEM_INFO,
    ),
  getServerCapabilities: async () =>
    callBaseMethod<Vokop.GetServerCapabilities>(
      Vokop.AvailableMethods.GET_SERVER_CAPABILITIES,
    ),
  getUiCapabilities: async () =>
    callBaseMethod<Vokop.GetUiCapabilities>(
      Vokop.AvailableMethods.GET_UI_CAPABILITIES,
    ),
  getUiState: async () =>
    callBaseMethod<Vokop.UiState>(
      Vokop.AvailableMethods.GET_UI_STATE,
      [],
      '/usr/bin/vokop',
      { timeout: GET_UI_STATE_RPC_TIMEOUT_MS },
    ),
  serviceActionStart: async (action: Vokop.ServiceAction) => {
    const response = await executeShellCommand({
      command: '/usr/bin/vokop',
      args: [Vokop.AvailableMethods.SERVICE_ACTION_ASYNC, action],
      timeout: UI_ACTION_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseUiActionStartResult(response);

    if (
      (response.code ?? 0) !== 0 ||
      !parsedResponse?.success ||
      !parsedResponse.job_id
    ) {
      return uiActionFailure(
        response,
        parsedResponse,
        _('Service action failed'),
      );
    }

    return {
      success: true,
      data: parsedResponse,
    } as Vokop.MethodSuccessResponse<Vokop.UiActionStartResult>;
  },
  serviceActionStatus: async (jobId: string) => {
    const response = await executeShellCommand({
      command: '/usr/bin/vokop',
      args: [Vokop.AvailableMethods.SERVICE_ACTION_STATUS, jobId],
      timeout: UI_ACTION_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseServiceActionState(response);

    if ((response.code ?? 0) !== 0 || !parsedResponse) {
      return uiActionFailure(
        response,
        parsedResponse,
        _('Service action failed'),
      );
    }

    return {
      success: true,
      data: parsedResponse,
    } as Vokop.MethodSuccessResponse<Vokop.ServiceActionState>;
  },
  waitServiceActionJob: async (jobId: string, startedAt = Date.now()) => {
    while (Date.now() - startedAt < SERVICE_ACTION_TIMEOUT_MS) {
      await sleep(SERVICE_ACTION_POLL_INTERVAL_MS);

      const response = await VokopShellMethods.serviceActionStatus(jobId);

      if (!response.success) {
        return response;
      }

      if (response.data.running) {
        continue;
      }

      return response;
    }

    return {
      success: false,
      error: _('Operation timed out'),
    } as Vokop.MethodFailureResponse;
  },
  latencyTestStart: async (
    latencyType: Vokop.LatencyActionState['latency_type'],
    section: string,
    tag: string,
    timeout?: string,
  ) => {
    const response = await executeShellCommand({
      command: '/usr/bin/vokop',
      args: [
        Vokop.AvailableMethods.LATENCY_TEST_ASYNC,
        latencyType,
        section,
        tag,
        ...(timeout ? [timeout] : []),
      ],
      timeout: UI_ACTION_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseUiActionStartResult(response);

    if (
      (response.code ?? 0) !== 0 ||
      !parsedResponse?.success ||
      !parsedResponse.job_id
    ) {
      return uiActionFailure(
        response,
        parsedResponse,
        _('Latency test failed'),
      );
    }

    return {
      success: true,
      data: parsedResponse,
    } as Vokop.MethodSuccessResponse<Vokop.UiActionStartResult>;
  },
  latencyTestStatus: async (jobId: string) => {
    const response = await executeShellCommand({
      command: '/usr/bin/vokop',
      args: [Vokop.AvailableMethods.LATENCY_TEST_STATUS, jobId],
      timeout: UI_ACTION_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseLatencyActionState(response);

    if ((response.code ?? 0) !== 0 || !parsedResponse) {
      return uiActionFailure(
        response,
        parsedResponse,
        _('Latency test failed'),
      );
    }

    return {
      success: true,
      data: parsedResponse,
    } as Vokop.MethodSuccessResponse<Vokop.LatencyActionState>;
  },
  waitLatencyTestJob: async (jobId: string, startedAt = Date.now()) => {
    const transientRpc = createTransientRpcGraceTracker(
      UI_ACTION_TRANSIENT_RPC_GRACE_MS,
    );

    while (Date.now() - startedAt < LATENCY_TEST_TIMEOUT_MS) {
      await sleep(LATENCY_TEST_POLL_INTERVAL_MS);

      const response = await VokopShellMethods.latencyTestStatus(jobId);

      if (!response.success) {
        if (transientRpc.shouldContinue(response.error)) {
          continue;
        }

        return response;
      }

      transientRpc.reset();
      if (response.data.running) {
        continue;
      }

      return response;
    }

    return {
      success: false,
      error: _('Operation timed out'),
    } as Vokop.MethodFailureResponse;
  },
  uiActionAck: async (
    kind: 'service' | 'latency' | 'component' | 'subscription',
    jobId: string,
  ) => {
    const response = await executeShellCommand({
      command: '/usr/bin/vokop',
      args: [Vokop.AvailableMethods.UI_ACTION_ACK, kind, jobId],
      timeout: UI_ACTION_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseUiActionStartResult(response);

    if ((response.code ?? 0) !== 0 || !parsedResponse?.success) {
      return uiActionFailure(response, parsedResponse);
    }

    return {
      success: true,
      data: parsedResponse,
    } as Vokop.MethodSuccessResponse<Vokop.UiActionStartResult>;
  },
  componentActionStart: async (
    component: Vokop.ComponentName,
    action: Vokop.ComponentAction,
  ) => {
    const response = await executeShellCommand({
      command: '/usr/bin/vokop',
      args: [Vokop.AvailableMethods.COMPONENT_ACTION_ASYNC, component, action],
      timeout: COMPONENT_ACTION_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseComponentActionStartResult(response);

    if (
      (response.code ?? 0) !== 0 ||
      !parsedResponse?.success ||
      !parsedResponse.job_id
    ) {
      return componentActionFailure(response, parsedResponse);
    }

    return {
      success: true,
      data: parsedResponse,
    } as Vokop.MethodSuccessResponse<Vokop.ComponentActionStartResult>;
  },
  componentActionStatus: async (jobId: string) => {
    const response = await executeShellCommand({
      command: '/usr/bin/vokop',
      args: [Vokop.AvailableMethods.COMPONENT_ACTION_STATUS, jobId],
      timeout: COMPONENT_ACTION_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseComponentActionResult(response);

    if ((response.code ?? 0) !== 0 || !parsedResponse) {
      return componentActionFailure(response, parsedResponse);
    }

    return {
      success: true,
      data: parsedResponse,
    } as Vokop.MethodSuccessResponse<Vokop.ComponentActionResult>;
  },
  componentUpdateCheckCache: async () =>
    callBaseMethod<Vokop.ComponentUpdateCheckCache>(
      Vokop.AvailableMethods.COMPONENT_UPDATE_CHECK_CACHE,
    ),
  waitComponentActionJob: async (
    jobId: string,
    component: Vokop.ComponentName,
    action: Vokop.ComponentAction,
    expectedLatestVersion?: string,
  ) => {
    let selfUpdateVersionMatchedAt = 0;
    let lastStatusRefreshAt = 0;
    const transientRpc = createTransientRpcGraceTracker(
      COMPONENT_ACTION_TRANSIENT_RPC_GRACE_MS,
    );

    while (true) {
      await sleep(COMPONENT_ACTION_POLL_INTERVAL_MS);

      const stateResponse = await readComponentActionState(jobId);

      if (stateResponse) {
        if (!stateResponse.running) {
          transientRpc.reset();
          return {
            success: true,
            data: stateResponse,
          } as Vokop.MethodSuccessResponse<Vokop.ComponentActionResult>;
        }

        if (
          Date.now() - lastStatusRefreshAt <
          COMPONENT_ACTION_STATUS_REFRESH_INTERVAL_MS
        ) {
          continue;
        }
      }

      lastStatusRefreshAt = Date.now();
      const statusResponse = await executeShellCommand({
        command: '/usr/bin/vokop',
        args: [Vokop.AvailableMethods.COMPONENT_ACTION_STATUS, jobId],
        timeout: COMPONENT_ACTION_RPC_TIMEOUT_MS,
      });
      const parsedResponse = parseComponentActionResult(statusResponse);

      if ((statusResponse.code ?? 0) !== 0 || !parsedResponse) {
        if (stateResponse?.running) {
          transientRpc.reset();
          continue;
        }

        if (await isComponentActionStillRunning(jobId, component, action)) {
          transientRpc.reset();
          continue;
        }

        const failure = componentActionFailure(statusResponse, parsedResponse);

        if (transientRpc.shouldContinue(failure.error)) {
          continue;
        }

        if (component === 'vokop' && action === 'install') {
          const installedVersion = expectedLatestVersion
            ? await readVokopVersion()
            : '';

          if (
            expectedLatestVersion &&
            installedVersion === expectedLatestVersion
          ) {
            if (!selfUpdateVersionMatchedAt) {
              selfUpdateVersionMatchedAt = Date.now();
            }

            if (
              Date.now() - selfUpdateVersionMatchedAt >=
              COMPONENT_ACTION_SELF_UPDATE_SETTLE_MS
            ) {
              return {
                success: true,
                data: {
                  success: true,
                  component,
                  action,
                  message: translate('Vokop has been installed'),
                  current_version: installedVersion,
                  latest_version: expectedLatestVersion,
                  changed: true,
                  status: 'latest',
                },
              } as Vokop.MethodSuccessResponse<Vokop.ComponentActionResult>;
            }
          }

          continue;
        }

        return failure;
      }

      transientRpc.reset();
      if (parsedResponse.running) {
        continue;
      }

      return {
        success: true,
        data: parsedResponse,
      } as Vokop.MethodSuccessResponse<Vokop.ComponentActionResult>;
    }
  },
  subscriptionUpdateStart: async (section?: string, sourceIndex?: number) => {
    const startArgs = [
      Vokop.AvailableMethods.SUBSCRIPTION_UPDATE_ASYNC,
      ...(section ? [section] : []),
      ...(section && sourceIndex !== undefined ? [String(sourceIndex)] : []),
    ];
    const response = await executeShellCommand({
      command: '/usr/bin/vokop',
      args: startArgs,
      timeout: SUBSCRIPTION_UPDATE_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseSubscriptionUpdateStartResult(response);

    if (
      (response.code ?? 0) !== 0 ||
      !parsedResponse?.success ||
      !parsedResponse.job_id
    ) {
      return {
        success: false,
        error:
          parsedResponse?.message ||
          response.stderr ||
          _('Subscription update failed'),
      } as Vokop.MethodFailureResponse;
    }

    return {
      success: true,
      data: parsedResponse,
    } as Vokop.MethodSuccessResponse<Vokop.SubscriptionUpdateStartResult>;
  },
  subscriptionUpdateStatus: async (jobId: string) => {
    const response = await executeShellCommand({
      command: '/usr/bin/vokop',
      args: [Vokop.AvailableMethods.SUBSCRIPTION_UPDATE_STATUS, jobId],
      timeout: SUBSCRIPTION_UPDATE_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseSubscriptionUpdateJobState(response);

    if ((response.code ?? 0) !== 0 || !parsedResponse) {
      return {
        success: false,
        error: response.stderr || _('Subscription update failed'),
      } as Vokop.MethodFailureResponse;
    }

    return {
      success: true,
      data: parsedResponse,
    } as Vokop.MethodSuccessResponse<Vokop.SubscriptionUpdateJobState>;
  },
  waitSubscriptionUpdateJob: async (jobId: string) => {
    const transientRpc = createTransientRpcGraceTracker(
      UI_ACTION_TRANSIENT_RPC_GRACE_MS,
    );

    while (true) {
      await sleep(SUBSCRIPTION_UPDATE_POLL_INTERVAL_MS);

      const response = await VokopShellMethods.subscriptionUpdateStatus(jobId);

      if (!response.success) {
        if (transientRpc.shouldContinue(response.error)) {
          continue;
        }

        return response;
      }

      transientRpc.reset();
      if (response.data.running) {
        continue;
      }

      return response;
    }
  },
};

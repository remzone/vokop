import type { Vokop } from '../../types';

export function shouldApplyCompletedComponentActionResult(
  result: Pick<Vokop.ComponentActionResult, 'action'>,
  notify: boolean,
) {
  return result.action !== 'check_update' || notify;
}

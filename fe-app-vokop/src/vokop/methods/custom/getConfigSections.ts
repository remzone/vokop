import { Vokop } from '../../types';
import { VOKOP_UCI_PACKAGE } from '../../../constants';

export async function getConfigSections(): Promise<Vokop.ConfigSection[]> {
  return uci
    .load(VOKOP_UCI_PACKAGE)
    .then(() => uci.sections(VOKOP_UCI_PACKAGE));
}

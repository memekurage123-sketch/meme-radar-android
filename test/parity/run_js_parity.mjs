import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { normalizeTokenAddress, normalizePoolAddress, validTokenAddress } from '../../../meme-radar-upstream/src/address.mjs';
import { chartRiskScreen } from '../../../meme-radar-upstream/src/chart-risk.mjs';
import { config } from '../../../meme-radar-upstream/src/config.mjs';
import { discoveryScreen, deepScreen } from '../../../meme-radar-upstream/src/scoring.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const fixtures = JSON.parse(fs.readFileSync(path.join(HERE, 'fixtures.json'), 'utf8'));

const results = {
  address: {},
  chart_risk: {},
  discovery: {},
  deep_screen: {}
};

// 1. Address cases
for (const tc of fixtures.address_cases) {
  if (tc.isPool) {
    results.address[tc.id] = {
      normalized: normalizePoolAddress(tc.chain, tc.address)
    };
  } else {
    results.address[tc.id] = {
      normalized: normalizeTokenAddress(tc.chain, tc.address),
      valid: validTokenAddress(tc.chain, tc.address)
    };
  }
}

// 2. Chart risk cases
for (const tc of fixtures.chart_risk_cases) {
  const res = chartRiskScreen(tc.candles, tc.now);
  results.chart_risk[tc.id] = {
    pass: res.pass,
    status: res.status,
    codes: res.codes,
    bars: res.bars,
    from: res.from,
    to: res.to
  };
}

// 3. Discovery cases
for (const tc of fixtures.discovery_cases) {
  const conf = { ...config, chain: tc.chain };
  const res = discoveryScreen(tc.row, conf, tc.nowSec);
  results.discovery[tc.id] = {
    pass: res.pass,
    reasons: [...res.reasons].sort(),
    priorityBand: res.priorityBand,
    score: Math.round(res.score * 100) / 100,
    mc: res.mc,
    liquidity: res.liquidity
  };
}

// 4. Deep screen cases
for (const tc of fixtures.deep_screen_cases) {
  const conf = { ...config, chain: tc.chain };
  const res = deepScreen({ discovery: tc.discovery, audit: tc.audit, nowMs: tc.nowMs }, conf);
  results.deep_screen[tc.id] = {
    chainPass: res.chainPass,
    failed: [...res.failed].sort(),
    checks: res.checks,
    honeypotEvidence: res.honeypotEvidence
  };
}

fs.writeFileSync(path.join(HERE, 'js_output.json'), JSON.stringify(results, null, 2));
console.log('JS parity runner finished successfully. Output written to js_output.json');

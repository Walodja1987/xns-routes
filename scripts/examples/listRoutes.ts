/**
 * Page through all routes registered under one XNS name using `getRouteEntries`.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/listRoutes.ts --network <network_name>`
 */

import hre from "hardhat";
import { XNS_ROUTES_ADDRESS } from "../../constants/addresses";

const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const RED = "\x1b[31m";

/*//////////////////////////////////////////////////////////////
                            USER INPUTS
//////////////////////////////////////////////////////////////*/

const label = "xns";
const namespace = "action";
const pageSize = 25n;

async function main() {
  const networkName = hre.network.name;
  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }

  const routes = await hre.ethers.getContractAt("XNSRoutes", contractAddress);
  const count = await routes["getRouteKeyCount(string,string)"](label, namespace);

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`XNS name: ${GREEN}${label}@${namespace}${RESET}`);
  console.log(`Route count: ${GREEN}${count}${RESET}\n`);

  if (count === 0n) {
    console.log(`${YELLOW}No routes found.${RESET}\n`);
    return;
  }

  for (let start = 0n; start < count; start += pageSize) {
    const end = start + pageSize;
    const entries = await routes["getRouteEntries(string,string,uint256,uint256)"](
      label,
      namespace,
      start,
      end,
    );

    for (const entry of entries) {
      const record = entry.record;
      console.log(`${label}@${namespace}/${record.routeLabel}`);
      console.log(`  key:       ${entry.routeKey}`);
      console.log(`  target:    ${record.target}`);
      console.log(`  routeType: ${record.routeType}`);
      console.log(`  active:    ${record.isActive}`);
      console.log(`  frozen:    ${record.isFrozen}`);
    }
  }

  console.log(`\n${GREEN}✓ Listed ${count} route(s).${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

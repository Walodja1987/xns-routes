/**
 * Read route metadata (target, isActive, isFrozen) from XNSRoutes.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/getRouteInfo.ts --network <network_name>`
 *
 * EXAMPLE:
 * `npx hardhat run scripts/examples/getRouteInfo.ts --network sepolia`
 *
 * REQUIRED SETUP:
 * - MNEMONIC, network RPC (see docs/DEV_NOTES.md)
 * - Set `XNS_ROUTES_ADDRESS.<network>` in constants/addresses.ts
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

/** XNS name that owns the route space (e.g. "xns.action") */
const xnsName = "xns.action";

/** Chain key (e.g. "eth" in `base/eth:route/...`) */
const chain = "eth";

/** Route label (e.g. "register-name") */
const route = "register-name";

async function main() {
  const networkName = hre.network.name;
  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }

  const routes = await hre.ethers.getContractAt("XNSRoutes", contractAddress);

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`xnsName: ${GREEN}${xnsName}${RESET}`);
  console.log(`chain: ${GREEN}${chain}${RESET}`);
  console.log(`route: ${GREEN}${route}${RESET}\n`);

  const exists = await routes.routeExists(xnsName, chain, route);
  if (!exists) {
    console.log(`${YELLOW}⚠${RESET} Route not found (no record).\n`);
    return;
  }

  const [target, isActive, isFrozen] = await routes.getRouteInfo(xnsName, chain, route);

  console.log(`target:   ${GREEN}${target}${RESET}`);
  console.log(`isActive: ${GREEN}${isActive}${RESET}`);
  console.log(`isFrozen: ${GREEN}${isFrozen}${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

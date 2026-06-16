/**
 * Read route metadata and route-book freeze status from XNSRoutes.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/getRouteRecord.ts --network <network_name>`
 *
 * EXAMPLE:
 * `npx hardhat run scripts/examples/getRouteRecord.ts --network sepolia`
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

/** Route scope (e.g. "eth" in `base/eth:route/...`) */
const routeScope = "eth";

/** Route label (e.g. "register-name") */
const routeLabel = "register-name";

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
  console.log(`routeScope: ${GREEN}${routeScope}${RESET}`);
  console.log(`routeLabel: ${GREEN}${routeLabel}${RESET}\n`);

  const details = await routes.getRouteRecordWithBookStatus(xnsName, routeScope, routeLabel);
  const record = details.record;
  if (record.target === hre.ethers.ZeroAddress) {
    console.log(`${YELLOW}⚠${RESET} Route not found (empty record).\n`);
    return;
  }

  const structurallyFrozen = record.isFrozen || details.isRouteBookFrozen;

  console.log(`target:    ${GREEN}${record.target}${RESET}`);
  console.log(`isActive:  ${GREEN}${record.isActive}${RESET}`);
  console.log(`isFrozen:  ${GREEN}${record.isFrozen}${RESET}`);
  console.log(`isRouteBookFrozen: ${GREEN}${details.isRouteBookFrozen}${RESET}`);
  console.log(`structurallyFrozen (isFrozen || isRouteBookFrozen): ${GREEN}${structurallyFrozen}${RESET}`);
  console.log(`routeType: ${GREEN}${record.routeType}${RESET}`);
  console.log(`activeController: ${GREEN}${record.activeController}${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

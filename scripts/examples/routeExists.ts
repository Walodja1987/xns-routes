/**
 * Check whether a route exists under an XNS name.
 *
 * Existence: `getRouteRecord(...).target.length == 0` (empty bytes / `"0x"`).
 *
 * USAGE:
 * `npx hardhat run scripts/examples/routeExists.ts --network <network_name>`
 *
 * EXAMPLE:
 * `npx hardhat run scripts/examples/routeExists.ts --network sepolia`
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

const label = "xns";
const namespace = "action";
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
  const xnsName = `${label}@${namespace}`;

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`xnsName: ${GREEN}${xnsName}${RESET}`);
  console.log(`routeLabel: ${GREEN}${routeLabel}${RESET}\n`);

  const record = await routes.getRouteRecord(label, namespace, routeLabel);
  const exists = hre.ethers.getBytes(record.target).length > 0;

  if (exists) {
    console.log(`${GREEN}✓${RESET} Route exists.\n`);
  } else {
    console.log(`${YELLOW}⚠${RESET} Route does not exist.\n`);
  }
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

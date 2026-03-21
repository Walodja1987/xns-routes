/**
 * Check whether all routes under a base XNS name are base-frozen
 * (no new routes / no target updates; activation may still toggle).
 *
 * USAGE:
 * `npx hardhat run scripts/examples/isBaseRoutesFrozen.ts --network <network_name>`
 *
 * EXAMPLE:
 * `npx hardhat run scripts/examples/isBaseRoutesFrozen.ts --network sepolia`
 *
 * REQUIRED SETUP:
 * - MNEMONIC, network RPC (see docs/DEV_NOTES.md)
 * - Set `XNS_ROUTES_ADDRESS.<network>` in constants/addresses.ts
 */

import hre from "hardhat";
import { keccak256, toUtf8Bytes } from "ethers";
import { XNS_ROUTES_ADDRESS } from "../../constants/addresses";

const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const RED = "\x1b[31m";

/*//////////////////////////////////////////////////////////////
                            USER INPUTS
//////////////////////////////////////////////////////////////*/

/** XNS name (e.g. "xns.action") */
const baseName = "xns.action";

async function main() {
  const networkName = hre.network.name;
  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }

  const routes = await hre.ethers.getContractAt("XNSRoutes", contractAddress);
  const baseKey = keccak256(toUtf8Bytes(baseName));
  const frozen = await routes.baseRoutesFrozen(baseKey);

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`baseName: ${GREEN}${baseName}${RESET}`);
  console.log(`baseKey: ${GREEN}${baseKey}${RESET}\n`);

  if (frozen) {
    console.log(
      `${YELLOW}⚠${RESET} Base routes are ${YELLOW}frozen${RESET} for this name (targets locked; new routes disabled).\n`,
    );
  } else {
    console.log(`${GREEN}✓${RESET} Base routes are ${GREEN}not${RESET} frozen.\n`);
  }
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

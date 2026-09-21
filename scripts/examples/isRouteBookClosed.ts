/**
 * Check whether the entire route book under an XNS name is closed
 * (no new routes; existing routes stay updatable until frozen; activation may still toggle).
 *
 * USAGE:
 * `npx hardhat run scripts/examples/isRouteBookClosed.ts --network <network_name>`
 *
 * EXAMPLE:
 * `npx hardhat run scripts/examples/isRouteBookClosed.ts --network sepolia`
 *
 * REQUIRED SETUP:
 * - MNEMONIC, network RPC (see docs/DEV_NOTES.md)
 * - Set `XNS_ROUTES_ADDRESS.<network>` in constants/addresses.ts
 */

import hre from "hardhat";
import { solidityPackedKeccak256 } from "ethers";
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
  const xnsNameKey = solidityPackedKeccak256(["string", "string", "string"], [label, "@", namespace]);
  const closed = await routes.isRouteBookClosed(xnsName);

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`xnsName: ${GREEN}${xnsName}${RESET}`);
  console.log(`xnsNameKey: ${GREEN}${xnsNameKey}${RESET}\n`);

  if (closed) {
    console.log(
      `${YELLOW}⚠${RESET} Route book is ${YELLOW}closed${RESET} for this name (new routes disabled).\n`,
    );
  } else {
    console.log(`${GREEN}✓${RESET} Route book is ${GREEN}not${RESET} closed.\n`);
  }
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

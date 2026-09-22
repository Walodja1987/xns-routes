/**
 * Read route metadata from XNSRoutes.
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

  const record = await routes["getRouteRecord(string,string,string)"](label, namespace, routeLabel);
  // Existence: empty bytes (`target.length == 0` / `"0x"`).
  if (record.target === "0x" || hre.ethers.getBytes(record.target).length === 0) {
    console.log(`${YELLOW}⚠${RESET} Route not found (empty record).\n`);
    return;
  }

  const bookClosed = await routes["isRouteBookClosed(string)"](xnsName);

  console.log(
    `target:    ${GREEN}${record.target}${RESET} (${hre.ethers.getBytes(record.target).length} bytes)`,
  );
  console.log(`isActive:  ${GREEN}${record.isActive}${RESET}`);
  console.log(`isFrozen:  ${GREEN}${record.isFrozen}${RESET}`);
  console.log(`isRouteBookClosed: ${GREEN}${bookClosed}${RESET}`);
  console.log(`routeType: ${GREEN}${record.routeType}${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

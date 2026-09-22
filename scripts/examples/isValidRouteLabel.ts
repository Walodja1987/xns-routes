/**
 * Check a route label against the contract's canonical validation rules.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/isValidRouteLabel.ts --network <network_name>`
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
  const valid = await routes.isValidRouteLabel(routeLabel);

  console.log(`\nRoute label: ${GREEN}${routeLabel}${RESET}`);
  console.log(
    valid ? `${GREEN}✓ Valid route label.${RESET}\n` : `${YELLOW}⚠ Invalid route label.${RESET}\n`,
  );
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

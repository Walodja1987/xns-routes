/**
 * Parse canonical XNS name and route strings with the contract's pure helpers.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/parseRoute.ts --network <network_name>`
 */

import hre from "hardhat";
import { XNS_ROUTES_ADDRESS } from "../../constants/addresses";

const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const RED = "\x1b[31m";

/*//////////////////////////////////////////////////////////////
                            USER INPUTS
//////////////////////////////////////////////////////////////*/

const xnsName = "xns@action";
const route = "xns@action/register-name";

async function main() {
  const networkName = hre.network.name;
  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }

  const routes = await hre.ethers.getContractAt("XNSRoutes", contractAddress);
  const [nameLabel, nameNamespace] = await routes.splitXNSName(xnsName);
  const [parsedLabel, parsedNamespace, parsedRouteLabel] = await routes.splitRoute(route);

  console.log(`\nXNS name: ${GREEN}${xnsName}${RESET}`);
  console.log(`  label:     ${nameLabel}`);
  console.log(`  namespace: ${nameNamespace}`);
  console.log(`Route: ${GREEN}${route}${RESET}`);
  console.log(`  label:      ${parsedLabel}`);
  console.log(`  namespace:  ${parsedNamespace}`);
  console.log(`  routeLabel: ${parsedRouteLabel}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

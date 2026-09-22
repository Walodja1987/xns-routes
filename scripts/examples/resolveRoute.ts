/**
 * Resolve a route using one of the three resolution policies.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/resolveRoute.ts --network <network_name>`
 */

import hre from "hardhat";
import { XNS_ROUTES_ADDRESS } from "../../constants/addresses";

const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const RED = "\x1b[31m";

/*//////////////////////////////////////////////////////////////
                            USER INPUTS
//////////////////////////////////////////////////////////////*/

const label = "xns";
const namespace = "action";
const routeLabel = "register-name";

/** `frozenAndActive` is the recommended production policy. */
const policy: "frozenAndActive" | "active" | "raw" = "frozenAndActive";

async function main() {
  const networkName = hre.network.name;
  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }

  const routes = await hre.ethers.getContractAt("XNSRoutes", contractAddress);

  let result: [string, bigint] & { target: string; routeType: bigint };
  if (policy === "frozenAndActive") {
    result = await routes["resolveRouteIfFrozenAndActive(string,string,string)"](
      label,
      namespace,
      routeLabel,
    );
  } else if (policy === "active") {
    result = await routes["resolveRouteIfActive(string,string,string)"](
      label,
      namespace,
      routeLabel,
    );
  } else {
    result = await routes["resolveRoute(string,string,string)"](label, namespace, routeLabel);
  }

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`Route: ${GREEN}${label}@${namespace}/${routeLabel}${RESET}`);
  console.log(`Policy: ${GREEN}${policy}${RESET}`);
  console.log(`target: ${GREEN}${result.target}${RESET}`);
  console.log(`routeType: ${GREEN}${result.routeType}${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

/**
 * Derive a canonical route key on-chain and compare it with ethers' local derivation.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/getRouteKey.ts --network <network_name>`
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

async function main() {
  const networkName = hre.network.name;
  const { ethers } = hre;
  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }

  const routes = await ethers.getContractAt("XNSRoutes", contractAddress);
  const route = `${label}@${namespace}/${routeLabel}`;
  const onchainKey = await routes["getRouteKey(string,string,string)"](
    label,
    namespace,
    routeLabel,
  );
  const stringOverloadKey = await routes["getRouteKey(string)"](route);
  const localKey = ethers.solidityPackedKeccak256(
    ["string", "string", "string", "string", "string"],
    [label, "@", namespace, "/", routeLabel],
  );

  console.log(`\nRoute: ${GREEN}${route}${RESET}`);
  console.log(`Tuple overload:  ${GREEN}${onchainKey}${RESET}`);
  console.log(`String overload: ${GREEN}${stringOverloadKey}${RESET}`);
  console.log(`Local ethers:    ${GREEN}${localKey}${RESET}`);

  if (onchainKey !== stringOverloadKey || onchainKey !== localKey) {
    throw new Error("Route key derivations do not match");
  }
  console.log(`\n${GREEN}✓ All route keys match.${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

/**
 * Update the target and route type of an unfrozen route.
 * Caller must be the current XNS owner of `label@namespace`.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/updateRoute.ts --network <network_name>`
 */

import hre from "hardhat";
import { formatEther } from "ethers";
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
const newTarget = "0x0000000000000000000000000000000000000002";
const newRouteType = 0;
const signerIndex = 0;

async function main() {
  const networkName = hre.network.name;
  const { ethers } = hre;
  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }
  if (ethers.getBytes(newTarget).length === 0) {
    throw new Error("newTarget must be non-empty bytes");
  }

  const routes = await ethers.getContractAt("XNSRoutes", contractAddress);
  const signer = (await ethers.getSigners())[signerIndex];

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`Signer: ${GREEN}${signer.address}${RESET}`);
  console.log(
    `Balance: ${GREEN}${formatEther(await ethers.provider.getBalance(signer.address))} ETH${RESET}`,
  );
  console.log(`Route: ${GREEN}${label}@${namespace}/${routeLabel}${RESET}`);
  console.log(`newTarget: ${GREEN}${newTarget}${RESET}`);
  console.log(`newRouteType: ${GREEN}${newRouteType}${RESET}\n`);

  const tx = await routes
    .connect(signer)
    .updateRoute(label, namespace, routeLabel, newTarget, newRouteType);
  console.log(`Transaction hash: ${GREEN}${tx.hash}${RESET}`);
  await tx.wait();

  const record = await routes["getRouteRecord(string,string,string)"](label, namespace, routeLabel);
  console.log(
    `${GREEN}✓ Confirmed. target=${record.target} routeType=${record.routeType}${RESET}\n`,
  );
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});

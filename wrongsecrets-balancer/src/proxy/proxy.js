const express = require('express');
const httpProxy = require('http-proxy');
const proxy = httpProxy.createProxyServer();
const cookieParser = require('cookie-parser');
const fs = require('fs');
const yaml = require('js-yaml');
const path = require('path'); // Add path module for easier file access

const { get, extractTeamName } = require('../config');
const { logger } = require('../logger');
const {
  getJuiceShopInstanceForTeamname,
  updateLastRequestTimestampForTeam,
} = require('../kubernetes');

const router = express.Router();

// ConfigMap Path (adjust if needed)
const configMapPath = '/etc/proxy-config/proxy-config.yaml';

// Load ConfigMap data (using path module for clarity)
let websocketConfig, proxyConfig;
try {
  const configFile = fs.readFileSync(path.join(__dirname, '..', '..', configMapPath), 'utf8');
  const configData = yaml.load(configFile);
  websocketConfig = configData.websocket;
  proxyConfig = configData.proxy;
  console.log('Loaded ConfigMap data:');
  console.log('WebSocket Config:', websocketConfig);
  console.log('Proxy Config:', proxyConfig);
} catch (error) {
  console.error('Error loading ConfigMap data:', error);
  process.exit(1);
}

// ... (rest of your code)

/**
 * @param {Express.Request} req
 * @param {Express.Response} res
 */
function proxyTrafficToJuiceShop(req, res) {
  const teamname = req.teamname;
  const url = req.url;

  // Check ConfigMap data for proxying decisions
  const websocketTarget = getWebSocketTarget(teamname, url, websocketConfig);
  const proxyTarget = getProxyTarget(teamname, url, proxyConfig);

  if (websocketTarget) {
    logger.info(`Proxying WebSocket request to ${websocketTarget.target}`);
    proxy.ws(req, res, {
      target: websocketTarget.target,
      ws: true,
    });
  } else if (proxyTarget) {
    logger.info(`Proxying request to ${proxyTarget.target}`);
    proxy.web(req, res, {
      target: proxyTarget.target,
      ws: true,
    }, (error) => {
      logger.warn(`Proxy fail '${error.code}' for: ${req.method.toLocaleUpperCase()} ${req.path}`);
      if (error.code !== 'ENOTFOUND' && error.code !== 'EHOSTUNREACH') {
        logger.error(error.message);
      } else {
        logger.debug(error.message);
      }
    });
  } else {
    logger.warn(`No proxy target found for ${teamname} and URL ${url}`);
    res.status(404).send('Not Found');
  }
}

// Helper functions to get proxy targets from ConfigMap data
function getWebSocketTarget(teamname, url, websocketConfig) {
  for (const [target, urls] of Object.entries(websocketConfig)) {
    if (urls.includes(url)) {
      // Use the target and teamname to construct the full URL
      return { target: `http://${teamname}-${target.split(':')[0]}.${teamname}.svc:${target.split(':')[1]}` };
    }
  }
  return null;
}

function getProxyTarget(teamname, url, proxyConfig) {
  for (const [target, urls] of Object.entries(proxyConfig)) {
    if (urls.some((u) => url.match(u))) {
      // Use the target and teamname to construct the full URL
      return { target: `http://${teamname}-${target.split(':')[0]}.${teamname}.svc:${target.split(':')[1]}` };
    }
  }
  return null;
}

// ... (rest of your code)

router.use(
  redirectJuiceShopTrafficWithoutBalancerCookies,
  redirectAdminTrafficToBalancerPage,
  checkIfInstanceIsUp,
  updateLastConnectTimestamp,
  proxyTrafficToJuiceShop
);

module.exports = router;
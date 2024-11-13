const express = require('express');
const httpProxy = require('http-proxy');
const proxy = httpProxy.createProxyServer();
const cookieParser = require('cookie-parser');
const fs = require('fs');
const yaml = require('js-yaml');

const configMapPath = '/etc/config/proxy-config.yaml';

const { get, extractTeamName } = require('../config');
const { logger } = require('../logger');
const {
  getJuiceShopInstanceForTeamname,
  updateLastRequestTimestampForTeam,
} = require('../kubernetes');

const router = express.Router();

// Load ConfigMap data
let websocketConfig, proxyConfig;
try {
  const configFile = fs.readFileSync(configMapPath, 'utf8');
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

/**
 * @param {import("express").Request} req
 * @param {import("express").Response} res
 * @param {import("express").NextFunction} next
 */
function redirectJuiceShopTrafficWithoutBalancerCookies(req, res, next) {
  if (!req.teamname) {
    logger.debug('Got request without team cookie in proxy. Redirecting to /balancer/');
    return res.redirect('/balancer/');
  }
  return next();
}

/**
 * @param {import("express").Request} req
 * @param {import("express").Response} res
 * @param {import("express").NextFunction} next
 */
function redirectAdminTrafficToBalancerPage(req, res, next) {
  if (req.teamname === `t-${get('admin.username')}`) {
    logger.debug('Got admin request in proxy. Redirecting to /balancer/');
    return res.redirect('/balancer/?msg=logged-as-admin');
  }
  return next();
}

const connectionCache = new Map();

/**
 * Checks at most every 10sec if the deployment the traffic should go to is ready.
 *
 * @param {import("express").Request} req
 * @param {import("express").Response} res
 * @param {import("express").NextFunction} next
 */
async function checkIfInstanceIsUp(req, res, next) {
  const teamname = req.cleanedTeamname;

  const currentTime = new Date().getTime();
  if (connectionCache.has(teamname) && currentTime - connectionCache.get(teamname) < 10000) {
    return next();
  }

  try {
    const { readyReplicas } = await getJuiceShopInstanceForTeamname(teamname);

    if (readyReplicas === 1) {
      return next();
    }

    logger.warn(`Tried to proxy for team ${teamname}, but no ready instance found.`);
    return res.redirect(`/balancer/?msg=instance-restarting&teamname=${teamname}`);
  } catch (error) {
    logger.warn(`Could not find instance for team: '${teamname}'`);
    logger.warn(JSON.stringify(error));
    res.redirect(`/balancer/?msg=instance-not-found&teamname=${teamname}`);
  }
}

/**
 * @param {import("express").Request} req
 * @param {import("express").Response} res
 * @param {import("express").NextFunction} next
 */
async function updateLastConnectTimestamp(req, res, next) {
  const currentTime = new Date().getTime();
  const teamname = req.cleanedTeamname;

  try {
    if (connectionCache.has(teamname)) {
      const timeDifference = currentTime - connectionCache.get(teamname);
      if (timeDifference > 10000) {
        connectionCache.set(teamname, currentTime);
        await updateLastRequestTimestampForTeam(teamname);
      }
    } else {
      await updateLastRequestTimestampForTeam(teamname);
      connectionCache.set(teamname, currentTime);
    }
  } catch (error) {
    logger.warn(`Failed to update lastRequest timestamp for team '${teamname}'"`);
    logger.warn(error.message);
    logger.warn(JSON.stringify(error));
  }
  next();
}

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
      return { target: `http://${teamname}-${target.split(':')[0]}.${teamname}.svc:${target.split(':')[1]}` };
    }
  }
  return null;
}

function getProxyTarget(teamname, url, proxyConfig) {
  for (const [target, urls] of Object.entries(proxyConfig)) {
    if (urls.some((u) => url.match(u))) {
      return { target: `http://${teamname}-${target.split(':')[0]}.${teamname}.svc:${target.split(':')[1]}` };
    }
  }
  return null;
}

router.use(
  redirectJuiceShopTrafficWithoutBalancerCookies,
  redirectAdminTrafficToBalancerPage,
  checkIfInstanceIsUp,
  updateLastConnectTimestamp,
  proxyTrafficToJuiceShop
);

module.exports = router;

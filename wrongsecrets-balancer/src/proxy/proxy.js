const express = require('express');
const httpProxy = require('http-proxy');
const proxy = httpProxy.createProxyServer();
const fs = require('fs');
const yaml = require('js-yaml');
const path = require('path');
const { logger } = require('../logger');

const router = express.Router();

// ConfigMap Path (adjust if needed)
const configMapPath = '/etc/proxy-config/proxy-config.yaml';

// Load ConfigMap data
let websocketConfig, proxyConfig;
try {
  const configFile = fs.readFileSync(path.join(__dirname, '..', '..', configMapPath), 'utf8');
  const configData = yaml.load(configFile);
  websocketConfig = configData.websocket;
  proxyConfig = configData.proxy;
  logger.info('Loaded ConfigMap data.');
} catch (error) {
  logger.error('Error loading ConfigMap data:', error);
  process.exit(1);
}

/**
 * Proxy Traffic Handler
 * @param {Express.Request} req
 * @param {Express.Response} res
 */
function proxyTrafficToJuiceShop(req, res) {
  const teamname = req.teamname;
  const url = req.url;

  const websocketTarget = getWebSocketTarget(teamname, url, websocketConfig);
  const proxyTarget = getProxyTarget(teamname, url, proxyConfig);

  if (websocketTarget) {
    logger.info(`Proxying WebSocket request to ${websocketTarget.target}`);
    proxy.ws(
      req,
      res,
      {
        target: websocketTarget.target,
        ws: true,
      }
    );
  } else if (proxyTarget) {
    logger.info(`Proxying request to ${proxyTarget.target}`);
  proxy.web(
    req,
    res,
    {
      target: proxyTarget.target,
      ws: true,
    },
    (error) => {
      logger.warn(
        `Proxy fail '${error.code}' for: ${req.method.toLocaleUpperCase()} ${req.path}`
      );
      if (error.code !== 'ENOTFOUND' && error.code !== 'EHOSTUNREACH') {
        logger.error(error.message);
      } else {
        logger.debug(error.message);
      }
    }
  );

  } else {
    logger.warn(`No proxy target found for ${teamname} and URL ${url}`);
    res.status(404).send('Not Found');
  }
}

// Helper functions (unchanged)
function getWebSocketTarget(teamname, url, websocketConfig) {
  // Implementation
}

function getProxyTarget(teamname, url, proxyConfig) {
  // Implementation
}

router.use(proxyTrafficToJuiceShop);

module.exports = router;

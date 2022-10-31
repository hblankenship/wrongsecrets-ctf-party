module.exports = {
  createK8sDeploymentForTeam: jest.fn(),
  createAWSDeploymentForTeam: jest.fn(),
  createNameSpaceForTeam: jest.fn(),
  createConfigmapForTeam: jest.fn(),
  createSecretsfileForTeam: jest.fn(),
  createDesktopDeploymentForTeam: jest.fn(),
  createServiceForTeam: jest.fn(),
  createDesktopServiceForTeam: jest.fn(),
  createServiceAccountForWebTop: jest.fn(),
  createNSPsforTeam: jest.fn(),
  createRoleForWebTop: jest.fn(),
  createRoleBindingForWebtop: jest.fn(),
  getJuiceShopInstanceForTeamname: jest.fn(() => ({
    readyReplicas: 1,
    availableReplicas: 1,
  })),
  getJuiceShopInstances: jest.fn(),
  deletePodForTeam: jest.fn(),
  updateLastRequestTimestampForTeam: jest.fn(),
  changePasscodeHashForTeam: jest.fn(),
};
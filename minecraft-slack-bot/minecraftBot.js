const {parse} = require('node:querystring');
const AWS = require('aws-sdk');
const axios = require('axios');

function parseCommandFromSlack(body) {
  const decodedData = Buffer.from(body, 'base64').toString('utf-8');
  const parsedBody = parse(decodedData);
  return {command: parsedBody.command.trim(), text: parsedBody.text.trim()}
}

function generateMinecraftServerCommand(command, text) {
  return ['start', 'stop', 'status'].includes(text) ? text : ''
}

async function invokeGithubAction(minecraftServerCommand) {
  // Retrieve GitHub Token from AWS Secrets Manager
  const secretsManager = new AWS.SecretsManager();
  const secretData = await secretsManager.getSecretValue({SecretId: 'github_token'}).promise();
  const githubToken = JSON.parse(secretData.SecretString)['GITHUB_TOKEN'];

  // Define the GitHub API endpoint URL
  const githubApiUrl = 'https://api.github.com/repos/gtempus/minecraft-terraform/dispatches';
  const data = JSON.stringify({
    "event_type": "custom_event",
    "client_payload": {
      "action": minecraftServerCommand,
    }
  });

  const config = {
    method: 'post',
    maxBodyLength: Infinity,
    url: githubApiUrl,
    headers: {
      'Accept': 'application/vnd.github.everest-preview+json',
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${githubToken}`
    },
    data: data,
  };
  // Make an HTTP POST request to trigger the GitHub Action
  const response =  await axios.request(config);
  console.log(`GitHub Action Response: ${response.status} ${response.data}`);
  return response.status;
}

exports.handler = async (event) => {
  console.log("Received event:", JSON.stringify(event, null, 2));

  // Slack sends a challenge parameter when you register an endpoint
  if (event.body?.challenge) {
    return {
      statusCode: 200,
      body: JSON.stringify({challenge: event.body.challenge}),
    };
  }

  // Parse the message from Slack
  const {command, text} = parseCommandFromSlack(event.body);

  // Convert Slack message to server command
  const minecraftServerCommand = generateMinecraftServerCommand(command, text);

  // send command to GitHub Action
  const githubResponse = await invokeGithubAction(minecraftServerCommand);

  // Send a message back to Slack
  return {
    statusCode: 200,
    body: "🫡 I'll get right on it! It takes ~5 minutes.\nOnce the server is up and running, I'll post the ip to #gamers_lair...",
  };
};

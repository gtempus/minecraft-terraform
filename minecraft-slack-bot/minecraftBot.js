const { parse } = require('querystring');
const AWS = require('aws-sdk');
const axios = require('axios');

const secretsManager = new AWS.SecretsManager();

exports.handler = async (event) => {
    console.log("Received event:", JSON.stringify(event, null, 2));

    // Slack sends a challenge parameter when you register an endpoint
    if (event.body && event.body.challenge) {
        return {
            statusCode: 200,
            body: JSON.stringify({ challenge: event.body.challenge }),
        };
    }

    // Parse the message from Slack
    const body = parse(event.body);
    console.log("Parsed body:", body);

    // kick off the github action
    // Retrieve GitHub Token from AWS Secrets Manager
    const secretData = await secretsManager.getSecretValue({ SecretId: 'github_token' }).promise();
    const githubToken = JSON.parse(secretData.SecretString).GITHUB_TOKEN;

    // Define the GitHub API endpoint URL
    const githubApiUrl = 'https://api.github.com/repos/gtempus/minecraft-terraform/dispatches';
    const data = JSON.stringify({
        "event_type": "custom_event",
        "client_payload": {
            "action": "start"
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
    const response = await axios.request(config);

    console.log({ response });

    // return {
    //     statusCode: response.status,
    //     body: JSON.stringify(response.data),
    // };

    const text = body.text || '';
    const responseMessage = `You said: ${text}`;

    // Send a message back to Slack
    return {
        statusCode: 200,
        body: JSON.stringify({ text: responseMessage }),
    };
};

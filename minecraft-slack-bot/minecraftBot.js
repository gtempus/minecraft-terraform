const { parse } = require('querystring');

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

    const text = body.text || '';
    const responseMessage = `You said: ${text}`;

    // Send a message back to Slack
    return {
        statusCode: 200,
        body: JSON.stringify({ text: responseMessage }),
    };
};

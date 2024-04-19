const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
require('dotenv').config();

admin.initializeApp();

const mailjetTransport = nodemailer.createTransport({
    host: "in-v3.mailjet.com",
    port: 587,
    auth: {
        user: "d0a559f4bc63c8a6871c011bb4bd1cdf",
        pass: "f8001a2619ea6e5b76e40edb15580e3a"
    }
});

exports.sendEmailNotification = functions.firestore
    .document('wasteData/{docId}')
    .onCreate(async (snap, context) => {
        const newValue = snap.data();

        // Get all users
        const users = await admin.auth().listUsers();
        const emails = users.users.map(user => user.email).filter(email => email);

        const mailOptions = {
            from: `CleanMapPro`,
            bcc: emails, // BCC all users
            subject: 'Waste detected in your area',
            text: `New waste data has been added: ${JSON.stringify(newValue)}`,
        };

        return mailjetTransport.sendMail(mailOptions)
            .then(() => console.log('Emails sent successfully'))
            .catch(error => console.error('Error sending emails:', error));
    });

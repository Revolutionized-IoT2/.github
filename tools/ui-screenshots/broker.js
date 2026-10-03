// Throwaway MQTT broker for screenshots: TCP on 127.0.0.2:1883 (avoids a local Mosquitto on 127.0.0.1) and WebSocket on 9001 for the UI.
const aedes = require('aedes')();
const { createServer } = require('aedes-server-factory');
createServer(aedes).listen(1883, '127.0.0.2', () => console.log('mqtt tcp 127.0.0.2:1883'));
createServer(aedes, { ws: true }).listen(9001, '127.0.0.1', () => console.log('mqtt ws 9001'));
const t = () => new Date().toISOString().slice(11, 19);
aedes.on('client', c => console.log(t(), 'CONNECT', c.id));
aedes.on('clientDisconnect', c => console.log(t(), 'DISCONNECT', c.id));
aedes.on('clientError', (c, e) => console.log(t(), 'CLIENTERROR', c && c.id, e.message));
aedes.on('subscribe', (s, c) => console.log(t(), 'SUB', c && c.id, s.map(x => x.topic + '@' + x.qos).join(',')));
aedes.on('publish', (p, c) => { if (!p.topic.startsWith('$SYS')) console.log(t(), 'PUB', c ? c.id : '-', p.topic, p.retain ? '(retained)' : '', String(p.payload).slice(0, 100)); });


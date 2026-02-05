const { WebSocketServer } = require('ws');

// Use the port provided by the host, or 8080 for local development
const PORT = process.env.PORT || 8080;

const wss = new WebSocketServer({ port: PORT });
const rooms = new Map(); // roomId -> { users: Set(ws), host: ws }

console.log(`SyncTube SaaS Server running on port ${PORT}`);

wss.on('connection', (ws) => {
    let currentRoomId = null;

    ws.on('message', (data) => {
        try {
            const message = JSON.parse(data);

            if (message.type === 'JOIN') {
                const { roomId, nickname } = message;
                if (!rooms.has(roomId)) {
                    rooms.set(roomId, { users: new Set(), host: ws });
                }
                
                const room = rooms.get(roomId);
                if (room.users.size >= 2) {
                    ws.send(JSON.stringify({ type: 'ERROR', message: 'Room is full' }));
                    return;
                }

                room.users.add(ws);
                currentRoomId = roomId;
                ws.nickname = nickname || 'Anonymous';
                
                const isHost = room.host === ws;
                console.log(`User ${ws.nickname} joined room: ${roomId} (Host: ${isHost})`);
                
                ws.send(JSON.stringify({ 
                    type: 'JOINED', 
                    roomId, 
                    isHost,
                    users: Array.from(room.users).map(u => u.nickname)
                }));

                // Notify others in the room
                broadcastToRoom(roomId, {
                    type: 'USER_JOINED',
                    nickname: ws.nickname,
                    users: Array.from(room.users).map(u => u.nickname)
                }, ws);
            }

            if (currentRoomId && rooms.has(currentRoomId)) {
                broadcastToRoom(currentRoomId, message, ws);
            }
        } catch (e) {
            console.error("Failed to process message:", e);
        }
    });

    ws.on('close', () => {
        if (currentRoomId && rooms.has(currentRoomId)) {
            const room = rooms.get(currentRoomId);
            room.users.delete(ws);
            console.log(`User ${ws.nickname} left room: ${currentRoomId}`);
            
            if (room.users.size === 0) {
                rooms.delete(currentRoomId);
                console.log(`Room ${currentRoomId} is now empty and has been deleted.`);
            } else {
                if (room.host === ws) {
                    room.host = room.users.values().next().value;
                    if (room.host) {
                        console.log(`New host assigned in room ${currentRoomId}: ${room.host.nickname}`);
                        room.host.send(JSON.stringify({ type: 'HOST_ASSIGNED' }));
                    }
                }
                broadcastToRoom(currentRoomId, {
                    type: 'USER_LEFT',
                    nickname: ws.nickname,
                    users: Array.from(room.users).map(u => u.nickname)
                });
            }
        }
    });

    function broadcastToRoom(roomId, message, sender) {
        const room = rooms.get(roomId);
        if (room) {
            room.users.forEach(client => {
                if (client !== sender && client.readyState === 1) { // WebSocket.OPEN
                    client.send(JSON.stringify(message));
                }
            });
        }
    }
});

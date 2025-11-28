# Firebase Realtime Database Schema for Heal Sphere

## Overview
This document defines the complete data structure for the Heal Sphere cancer support app using Firebase Realtime Database.

## Security Rules Summary
- `/awareness`: Public read, no write
- `/bookmarks/$uid`: Private per user
- `/users/$uid`: Private per user
- `/patients`: Read by authenticated users, write by clinicians only
- `/caregivers`: Read by authenticated users, write by clinicians only
- `/chats/$chatId`: Read/write by participants only
- `/userChats/$uid`: Private per user

---

## 1. `/awareness` - Public Awareness Content

### Structure:
```json
{
  "awareness": {
    "carousel": {
      "$newsId": {
        "id": "string",
        "title": "string",
        "description": "string",
        "link": "string (URL)",
        "imageUrl": "string (URL, optional)",
        "timestamp": "number (milliseconds)"
      }
    },
    "education": {
      "$educationId": {
        "id": "string",
        "title": "string (e.g., 'Breast Cancer')",
        "short": "string (short description)",
        "details": "string (full details: symptoms, treatment, prevention)",
        "moreLink": "string (URL, optional)"
      }
    },
    "feed": {
      "$articleId": {
        "id": "string",
        "title": "string",
        "description": "string",
        "link": "string (URL)",
        "imageUrl": "string (URL, optional)",
        "timestamp": "number (milliseconds)"
      }
    }
  }
}
```

### Example:
```json
{
  "awareness": {
    "carousel": {
      "news1": {
        "id": "news1",
        "title": "Latest Cancer Research Breakthrough",
        "description": "Scientists discover new treatment method...",
        "link": "https://example.com/article1",
        "imageUrl": "https://example.com/image1.jpg",
        "timestamp": 1704067200000
      }
    },
    "education": {
      "edu1": {
        "id": "edu1",
        "title": "Breast Cancer",
        "short": "Most common cancer in women",
        "details": "Symptoms: lumps, changes in breast shape... Treatment: surgery, chemotherapy... Prevention: regular screening...",
        "moreLink": "https://who.int/cancer"
      }
    }
  }
}
```

---

## 2. `/bookmarks/$uid` - User Bookmarks

### Structure:
```json
{
  "bookmarks": {
    "$uid": {
      "$itemId": {
        "savedAt": "number (timestamp)",
        "title": "string",
        "link": "string (URL)",
        "type": "string (optional: 'news', 'education', 'article')"
      }
    }
  }
}
```

### Example:
```json
{
  "bookmarks": {
    "user123": {
      "news1": {
        "savedAt": 1704067200000,
        "title": "Latest Cancer Research",
        "link": "https://example.com/article1",
        "type": "news"
      }
    }
  }
}
```

---

## 3. `/users/$uid` - User Profiles

### Structure:
```json
{
  "users": {
    "$uid": {
      "uid": "string (same as $uid)",
      "name": "string",
      "email": "string",
      "role": "string ('patient' | 'caregiver' | 'clinician')",
      "phone": "string (optional)",
      "photoUrl": "string (URL, optional)",
      "linkedPatientId": "string (for patients/caregivers, optional)",
      "createdAt": "string (ISO8601) or number (timestamp)",
      "updatedAt": "string (ISO8601) or number (timestamp)"
    }
  }
}
```

### Example:
```json
{
  "users": {
    "user123": {
      "uid": "user123",
      "name": "Dr. John Smith",
      "email": "doctor@example.com",
      "role": "clinician",
      "phone": "+1234567890",
      "createdAt": "2024-01-01T00:00:00Z"
    }
  }
}
```

---

## 4. `/patients` - Patient Records

### Structure:
```json
{
  "patients": {
    "$patientId": {
      "id": "string (same as $patientId)",
      "name": "string",
      "age": "number (optional)",
      "gender": "string ('Male' | 'Female' | 'Other')",
      "diagnosis": "string",
      "diagnosisDate": "number (timestamp, optional)",
      "conditionSummary": "string (optional)",
      "photoUrl": "string (URL, optional)",
      "clinicianId": "string (UID of assigned clinician)",
      "caregiverId": "string (ID from /caregivers, optional)",
      "caregiverUserUid": "string (UID of caregiver user, optional)",
      "patientUserUid": "string (UID of patient user account, optional)",
      "needsFollowUp": "boolean",
      "followUpNote": "string (optional)",
      "followUpRequestedAt": "number (timestamp, optional)",
      "doctorNotes": "string (optional)",
      "progressSummary": "string (optional)",
      "chemoHistory": {
        "$chemoId": {
          "id": "string",
          "date": "number (timestamp)",
          "completed": "boolean",
          "remarks": "string (optional)",
          "notes": "string (optional)"
        }
      },
      "appointments": {
        "$appointmentId": {
          "id": "string",
          "datetime": "number (timestamp)",
          "notes": "string (optional)",
          "status": "string ('scheduled' | 'completed' | 'cancelled')",
          "createdAt": "number (timestamp)"
        }
      },
      "medicines": {
        "$medicineId": {
          "id": "string",
          "name": "string",
          "time": "string (e.g., 'Morning')",
          "frequency": "string (e.g., 'Daily')",
          "dosage": "string (optional)"
        }
      },
      "dailyLogs": {
        "$logId": {
          "id": "string",
          "date": "number (timestamp)",
          "eating": "string ('Poor' | 'Average' | 'Good')",
          "sleepHours": "number",
          "feeling": "string (e.g., 'Happy', 'Calm', 'Anxious', 'Sad', 'Tired', 'In Pain')",
          "activities": ["string (array of activities)"]
        }
      },
      "activities": {
        "$activityId": {
          "id": "string",
          "description": "string",
          "date": "number (timestamp)",
          "createdBy": "string (UID)"
        }
      },
      "createdAt": "number (timestamp)",
      "updatedAt": "number (timestamp)"
    }
  }
}
```

### Example:
```json
{
  "patients": {
    "patient1": {
      "id": "patient1",
      "name": "Jane Doe",
      "age": 45,
      "gender": "Female",
      "diagnosis": "Breast Cancer Stage 2",
      "diagnosisDate": 1704067200000,
      "clinicianId": "doctor123",
      "patientUserUid": "user456",
      "needsFollowUp": false,
      "chemoHistory": {
        "chemo1": {
          "id": "chemo1",
          "date": 1704153600000,
          "completed": true,
          "remarks": "First session completed successfully"
        }
      },
      "appointments": {
        "app1": {
          "id": "app1",
          "datetime": 1704240000000,
          "notes": "Follow-up consultation",
          "status": "scheduled"
        }
      }
    }
  }
}
```

---

## 5. `/caregivers` - Caregiver Records

### Structure:
```json
{
  "caregivers": {
    "$caregiverId": {
      "id": "string (same as $caregiverId)",
      "name": "string",
      "phone": "string",
      "email": "string (optional)",
      "linkedPatientId": "string (ID from /patients)",
      "uid": "string (UID from /users, optional - if caregiver has user account)",
      "createdAt": "number (timestamp)",
      "updatedAt": "number (timestamp)"
    }
  }
}
```

### Example:
```json
{
  "caregivers": {
    "caregiver1": {
      "id": "caregiver1",
      "name": "John Doe",
      "phone": "+1234567890",
      "linkedPatientId": "patient1",
      "uid": "user789",
      "createdAt": 1704067200000
    }
  }
}
```

---

## 6. `/chats/$chatId` - Chat Conversations

### Structure:
```json
{
  "chats": {
    "$chatId": {
      "id": "string (same as $chatId)",
      "createdAt": "number (timestamp)",
      "lastMessage": "string",
      "lastTimestamp": "number (timestamp)",
      "participants": {
        "$uid": true
      },
      "messages": {
        "$messageId": {
          "id": "string",
          "senderId": "string (UID)",
          "text": "string",
          "createdAt": "number (timestamp)",
          "type": "string (optional: 'text', 'image', etc.)"
        }
      }
    }
  }
}
```

### Example:
```json
{
  "chats": {
    "chat123": {
      "id": "chat123",
      "createdAt": 1704067200000,
      "lastMessage": "Hello, how are you?",
      "lastTimestamp": 1704067300000,
      "participants": {
        "user123": true,
        "user456": true
      },
      "messages": {
        "msg1": {
          "id": "msg1",
          "senderId": "user123",
          "text": "Hello, how are you?",
          "createdAt": 1704067300000,
          "type": "text"
        }
      }
    }
  }
}
```

---

## 7. `/userChats/$uid` - User Chat Metadata

### Structure:
```json
{
  "userChats": {
    "$uid": {
      "$chatId": {
        "peerId": "string (UID of other participant)",
        "peerName": "string",
        "lastMessage": "string",
        "lastTimestamp": "number (timestamp)"
      }
    }
  }
}
```

### Example:
```json
{
  "userChats": {
    "user123": {
      "chat123": {
        "peerId": "user456",
        "peerName": "Jane Doe",
        "lastMessage": "Hello, how are you?",
        "lastTimestamp": 1704067300000
      }
    }
  }
}
```

---

## Data Relationships

1. **User → Patient**: 
   - Patient user has `linkedPatientId` in `/users/$uid`
   - Patient record has `patientUserUid` in `/patients/$patientId`

2. **User → Caregiver**:
   - Caregiver user has `linkedPatientId` in `/users/$uid`
   - Caregiver record has `uid` in `/caregivers/$caregiverId`
   - Patient record has `caregiverUserUid` in `/patients/$patientId`

3. **Clinician → Patient**:
   - Patient record has `clinicianId` in `/patients/$patientId`
   - Query: `/patients` where `clinicianId == $clinicianUid`

4. **Chat Participants**:
   - Chat has `participants` map with UIDs
   - Each user has chat metadata in `/userChats/$uid`

---

## Notes

- All timestamps are in milliseconds since epoch (Unix timestamp * 1000)
- Use `ServerValue.timestamp` when writing to get server timestamp
- IDs should match the key in the path for consistency
- Optional fields can be omitted from records
- Arrays in Firebase are stored as maps with numeric keys



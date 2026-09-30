# AirAware Pune: Student Viva Handbook & Practical Exam Defense Guide

This handbook is designed specifically for students presenting the **AirAware Pune** real-time air quality platform for project evaluations, DBMS practical exams, and viva examinations. It covers architectural justification, database design, live demo walk-throughs, and answers to common examiner questions.

---

## 1. The 2-Minute Elevator Pitch

> *"AirAware is an enterprise-grade, mobile-first environmental telemetry platform engineered specifically for the city of Pune. Unlike static dashboards or mock prototypes, AirAware streams real-time pollutant telemetry ($PM_{2.5}, PM_{10}, NO_2, SO_2, CO, O_3$) from 49 ground stations into a Supabase PostgreSQL database accelerated with PostGIS spatial indexing. The mobile application, built with Flutter, provides Pune citizens with hyper-local air quality indices, a foreground GPS outdoor exposure dosage tracker that calculates inhaled particulate matter in micrograms, a Community Watch reporting system with live GPS coordinates, and 5 personalized health profiles that adapt medical advisories to vulnerable demographics."*

---

## 2. Key Architecture & Tech Stack

| Tier | Technology | Why We Chose It |
| :--- | :--- | :--- |
| **Mobile Client** | **Flutter (Dart 3.x)** | Cross-platform native compilation, 60fps vector maps, hardware GPS integration, and robust state management via Riverpod. |
| **Backend API** | **FastAPI (Python 3.11)** | Asynchronous high-throughput REST API, automatic OpenAPI validation via Pydantic, and fast integration with scientific libraries. |
| **Database** | **Supabase (PostgreSQL 15)** | ACID compliance, native relational constraints, Row Level Security (RLS), and real-time Change Data Capture (CDC) via WebSockets. |
| **Spatial Engine** | **PostGIS 3.3** | Specialized GIST R-Tree spatial indexing for sub-2ms nearest-station lookups and polygon boundary containment queries. |
| **Notifications** | **Flutter Local Notifications** | Native Android 13+ Notification Channels (`POST_NOTIFICATIONS`) with hardware vibration and cooldown deduplication. |

---

## 3. Database Design & DBMS Justification

### 3.1 Normalization (3NF / BCNF)
- The schema is normalized to **Third Normal Form (3NF)**:
  - Every non-key attribute depends strictly on the primary key, the whole primary key, and nothing but the primary key.
  - Station metadata (`name`, `ward`, `operator`, `geom`) is separated from high-frequency time-series telemetry (`air_quality_readings`).
  - Redundant string duplication is prevented using foreign key references (`station_id`, `user_id`).
  - Selective denormalization (`latest_aqi` on `stations`) is maintained via database triggers to achieve $O(1)$ read performance on the main map screen without complex grouping aggregations on millions of historical readings.

### 3.2 Strong vs. Weak Entities
- **Strong Entities**: `stations`, `wards`, `pollutants`, `auth.users`. They exist independently and possess primary keys not derived from parent entities.
- **Weak Entities**: `air_quality_readings`, `station_sensors`, `exposure_sessions`, `report_upvotes`. They have existential dependency on their parent entities and include `ON DELETE CASCADE` or `ON DELETE SET NULL` constraints.

### 3.3 PostGIS Spatial Indexing
- Standard B-Tree indexes cannot efficiently index 2-dimensional geographic coordinates $(\text{latitude}, \text{longitude})$.
- AirAware uses **Generalized Search Trees (GIST)** implementing an R-Tree index:
  ```sql
  CREATE INDEX idx_stations_geom ON stations USING GIST (geom);
  CREATE INDEX idx_wards_boundary ON wards USING GIST (boundary);
  ```
- This allows spatial queries (`ST_DWithin`, `ST_Distance`, and the `<->` KNN operator) to execute in logarithmic time $O(\log N)$ rather than scanning every row $O(N)$.

---

## 4. Top Viva Questions & Model Answers

### Q1: Why did you choose PostgreSQL + PostGIS over a NoSQL database like MongoDB?
**Answer**:
> *"Air quality monitoring involves strict relationships between geographic boundaries (PMC Wards), physical monitoring stations, authenticated citizens, and verified incident reports. PostgreSQL provides ACID guarantees and foreign key constraints to prevent orphaned records. Furthermore, PostGIS is the global industry standard for geospatial computing, offering exact geodetic distance calculations (`ST_Distance` on geography) and spatial polygon containment (`ST_Contains`), which NoSQL engines handle with significantly less efficiency and mathematical precision."*

---

### Q2: How is the Indian CPCB AQI calculated in the app?
**Answer**:
> *"The Indian National Air Quality Index (CPCB) evaluates 8 criteria pollutants ($PM_{2.5}, PM_{10}, NO_2, SO_2, CO, O_3, NH_3, Pb$). For each pollutant, a sub-index $I$ is calculated using linear piecewise interpolation:
> $$I = \frac{I_{high} - I_{low}}{B_{high} - B_{low}} \times (C - B_{low}) + I_{low}$$
> The overall AQI is the maximum of all calculated sub-indices:
> $$\text{AQI} = \max(I_{PM_{2.5}}, I_{PM_{10}}, I_{NO_2}, \dots)$$
> To be valid under national standards, at least 3 pollutants must be monitored, with at least one particulate matter pollutant ($PM_{2.5}$ or $PM_{10}$). The resulting index is categorized into 6 standard health categories: Good (0–50), Satisfactory (51–100), Moderate (101–200), Poor (201–300), Very Poor (301–400), and Severe (401–500+)."*

---

### Q3: How does the Exposure Mode calculate the inhaled dosage of pollution?
**Answer**:
> *"Exposure Mode tracks user movement via Android GPS and samples ambient $PM_{2.5}$ from the nearest ground station every 15 seconds. It computes inhaled particulate dosage in micrograms ($\mu g$) using clinical minute ventilation formulas:
> $$\text{Dosage } (\mu g) = \sum \left( C_{PM_{2.5}} \times V_E \times \Delta t \right)$$
> Where $V_E$ is the minute ventilation volume based on the selected activity: $0.008 \, m^3/\text{min}$ for rest/walking, and $0.035 \, m^3/\text{min}$ for running or cycling. When tracking ends, the total dosage, distance, duration, and peak AQI are recorded in the `exposure_sessions` table in Supabase."*

---

### Q4: How does the application prevent notification spam when AQI is elevated?
**Answer**:
> *"We implemented a 30-minute cooldown suppression engine in `NotificationService.dart`. When local AQI exceeds the citizen's personalized threshold, the app checks the timestamp of the last dispatched notification. If less than 30 minutes have elapsed, the notification is suppressed, ensuring the user is alerted to dangerous spikes without receiving disruptive repeated alerts."*

---

### Q5: How do the 5 Health Personas impact the user experience?
**Answer**:
> *"Different individuals have vastly different physiological sensitivities to air pollution. AirAware provides 5 personas: General Public, Asthmatic/Respiratory, Children/Schools, Elderly/Cardiac, and Athletes. In the code, the user's active persona dynamically re-evaluates risk thresholds. For example, an asthmatic user receives high-risk alerts at $PM_{2.5} > 60 \, \mu g/m^3$, whereas a general user is alerted at $PM_{2.5} > 90 \, \mu g/m^3$. Persona contexts are also injected into the Gemini AI Assistant prompt so that medical advice is personalized."*

---

### Q6: Why did you eliminate the web interface and focus exclusively on mobile?
**Answer**:
> *"Air quality exposure is fundamentally mobile and location-dependent. Citizens jog, cycle, and commute outdoors where desktop web browsers cannot track GPS distance, calculate moving inhaled dosages, or dispatch native Android foreground notifications. By focusing 100% of our engineering effort on a native Android mobile experience, we delivered high-fidelity GPS tracking, background location services, and instant offline-first caching without wasting resources maintaining redundant static web assets."*

---

## 5. Step-by-Step Live Demo Script for Evaluators

1. **Launch & Pre-Warming**:
   - Open the app on the Android phone.
   - Point out the smooth animated splash screen pre-warming 49 Pune stations in the background.
2. **Executive Home Dashboard**:
   - Highlight the **City Pulse Header** showing current Pune-wide average AQI and dominant pollutant.
   - Show the **Dynamic Health Advisor** reflecting the selected user persona.
3. **Interactive Vector Map**:
   - Navigate to the **Map** tab.
   - Show the 49 color-coded station pins across Pune.
   - Tap the **Recenter Button** (point out it has no overlap with the navigation bar) to zoom directly to your real device GPS location.
   - Tap a station (e.g. Shivajinagar or Kothrud) to open the modal card showing real $PM_{2.5}, PM_{10}, NO_2$ levels.
4. **Outdoor Exposure Tracker**:
   - Switch to the **Exposure** tab.
   - Select "Running" or "Cycling" and tap **Start Tracking**.
   - Pull down the Android notification shade: point out the active foreground service notification (`AirAware Exposure Tracker Active`).
   - Walk a few meters: observe distance updating, nearest station being resolved, and inhaled dosage ($\mu g$) accumulating in real-time.
   - Tap **Stop Tracking**: show the session summary and mention it is now saved to Supabase.
5. **Community Watch & Citizen Reporting**:
   - Switch to the **Alerts** tab.
   - Show the list of live community pollution reports.
   - Tap **Report Pollution Incident**: note that device GPS latitude and longitude are automatically fetched.
   - Tap an existing report's **Upvote** button: watch the counter increment in real-time.
   - Tap **Test Notification**: demonstrate immediate high-priority notification delivery with vibration.
6. **Profile & Persona Customization**:
   - Switch to the **Profile** tab.
   - Tap **Edit Profile**: update display name and demonstrate persistence to the `profiles` table.
   - Select the **Asthmatic** persona: return to Home and demonstrate that health advice and warnings have immediately tailored to respiratory precautions.

#include "simulator.hpp"
#include <iostream>
#include <fstream>
#include <set>
#include <mutex>
#include "types.hpp"
#include <nlohmann/json.hpp>
#include <drogon/drogon.h>
#include <drogon/WebSocketController.h>
#include <drogon/HttpAppFramework.h>

using json = nlohmann::json;
using namespace drogon;

// Global state for WebSocket logic
static std::mutex g_connections_mutex;
static std::set<WebSocketConnectionPtr> g_connections;
static simulator::Simulator* g_sim = nullptr;

/**
 * Context to store session information for a WebSocket connection.
 */
struct ConnectionContext {
    std::string sid;
    bool connected{false};
};

/**
 * WebSocket Controller for Socket.IO emulation.
 * Drogon handles WebSocket upgrades and message routing via this class.
 */
class SocketIOController : public WebSocketController<SocketIOController> {
public:
    void handleNewMessage(const WebSocketConnectionPtr& conn, std::string&& message, const WebSocketMessageType& type) override {
        // std::cout << "[WS] Message from " << conn->peerAddr().toIpPort() << ": " << message << std::endl;
        
        // Handle Engine.IO ping (2) -> pong (3)
        if (message == "2") {
            conn->send("3");
        } 
        // Handle Engine.IO probe (2probe) -> 3probe
        else if (message == "2probe") {
            conn->send("3probe");
        }
        // Handle Socket.IO Connect to default namespace (40)
        else if (message.length() >= 2 && message.substr(0, 2) == "40") {
            auto ctx = conn->getContext<ConnectionContext>();
            if (ctx && !ctx->connected) {
                ctx->connected = true;
                // Standard v4 connect ack for default namespace. 
                // Many clients expect the SID in the connect response too.
                conn->send("40{\"sid\":\"" + ctx->sid + "\"}");
                std::cout << "[WS] Session " << ctx->sid << " authorized for namespace" << std::endl;
            } else if (ctx && ctx->connected) {
                // Already connected, just ack
                conn->send("40{\"sid\":\"" + ctx->sid + "\"}");
            }
        }
    }

    void handleNewConnection(const HttpRequestPtr& req, const WebSocketConnectionPtr& conn) override {
        const std::string& origin = req->getHeader("Origin").empty() ? req->getHeader("origin") : req->getHeader("Origin");
        
        {
            std::lock_guard<std::mutex> lock(g_connections_mutex);
            g_connections.insert(conn);
        }
        
        // Generate a standard-looking alphanumeric SID that is actually unique
        std::string sid = "ws_" + std::to_string(std::chrono::system_clock::now().time_since_epoch().count() % 1000000) 
                        + "_" + std::to_string(rand() % 10000);
        conn->setContext(std::make_shared<ConnectionContext>(ConnectionContext{sid, false}));

        std::cout << "[WS] Client handshaking from " << conn->peerAddr().toIpPort() 
                  << " -> Assigned SID: " << sid << std::endl;

        // Engine.IO v4 Handshake
        nlohmann::json handshake = {
            {"sid", sid},
            {"upgrades", nlohmann::json::array()},
            {"pingInterval", 25000},
            {"pingTimeout", 20000}
        };
        
        // 1. Send Engine.IO Open packet
        std::string open_packet = "0" + handshake.dump();
        conn->send(open_packet);
        
        // We do NOT send '40' here. We wait for client to send '40' and then we acknowledge it in handleNewMessage.
        // This avoids the double-connection / timeout issues seen previously.
    }

    void handleConnectionClosed(const WebSocketConnectionPtr& conn) override {
        {
            std::lock_guard<std::mutex> lock(g_connections_mutex);
            g_connections.erase(conn);
        }
        std::cout << "[WS] Client disconnected" << std::endl;
    }

    WS_PATH_LIST_BEGIN
    WS_PATH_ADD("/socket.io/");
    WS_PATH_ADD("/socket.io");
    WS_PATH_LIST_END
};

int main(int argc, char* argv[]) {
    // Seed randomness for SID generation
    srand(static_cast<unsigned int>(time(NULL)));

    // Disable stdout buffering for immediate feedback in Cloud Run logs
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    try {
        std::cout << "Starting C++ Simulator Server (Drogon)..." << std::endl;
        
        // --- 1. Load Configuration ---
        std::string config_path = "config.json";
        if (argc > 1) config_path = argv[1];

        std::cout << "Loading config from " << config_path << "..." << std::endl;
        std::ifstream f(config_path);
        nlohmann::json config_json;
        if (f.is_open()) {
            f >> config_json;
        } else {
            std::cerr << "Warning: Could not open config file: " << config_path << ", using defaults." << std::endl;
            config_json["symbols"] = {"AAPL", "GOOGL", "MSFT", "AMZN", "TSLA"};
            config_json["currencies"] = {"USD", "EUR"};
            config_json["venues"] = {"NASDAQ", "NYSE"};
            config_json["periodicityMs"] = 1000;
            config_json["priceVariationPercentage"] = 0.5;
            config_json["gcpProjectId"] = "google.com:cl-data-cloud-field-ops";
        }

        simulator::Config config = config_json.get<simulator::Config>();
        
        // Override with environment variables
        if (const char* proj_id = std::getenv("PROJECT_ID")) config.gcp_project_id = proj_id;
        if (const char* ds_id = std::getenv("BIGQUERY_DATASET_ID")) config.bigquery_dataset_id = ds_id;
        if (const char* tb_id = std::getenv("BIGQUERY_TABLE_ID")) config.bigquery_table_id = tb_id;
        
        // Default values for common GCP project structure if still empty
        if (config.bigquery_dataset_id.empty()) config.bigquery_dataset_id = "paywall_datasets";
        if (config.bigquery_table_id.empty()) config.bigquery_table_id = "bidask_all_staged";

        // --- 2. Initialize Simulator ---
        std::cout << "Initializing Simulator for project " << config.gcp_project_id << "..." << std::endl;
        simulator::Simulator sim(config);
        g_sim = &sim;

        // Set up simulator callbacks for real-time WebSocket updates
        sim.SetCallbacks(
            [](const simulator::PricingMessage& msg) {
                std::lock_guard<std::mutex> lock(g_connections_mutex);
                std::string payload = "42[\"message\"," + nlohmann::json(msg).dump() + "]";
                for (auto& conn : g_connections) {
                    auto ctx = conn->getContext<ConnectionContext>();
                    if (ctx && ctx->connected) {
                        conn->send(payload);
                    }
                }
            },
            [](const simulator::PriceUpdate& pu) {
                std::lock_guard<std::mutex> lock(g_connections_mutex);
                std::string payload = "42[\"priceUpdate\"," + nlohmann::json(pu).dump() + "]";
                for (auto& conn : g_connections) {
                    auto ctx = conn->getContext<ConnectionContext>();
                    if (ctx && ctx->connected) {
                        conn->send(payload);
                    }
                }
            },
            [](const simulator::BurstProgress& prog) {
                std::lock_guard<std::mutex> lock(g_connections_mutex);
                std::string payload = "42[\"burstProgress\"," + nlohmann::json(prog).dump() + "]";
                for (auto& conn : g_connections) {
                    auto ctx = conn->getContext<ConnectionContext>();
                    if (ctx && ctx->connected) {
                        conn->send(payload);
                    }
                }
            }
        );

        // --- 3. Drogon Configuration (Global Middlewares) ---
        
        // Log all incoming requests for debugging
        app().registerPreRoutingAdvice([](const HttpRequestPtr &req, std::function<void(const HttpResponsePtr &)> &&cb, std::function<void()> &&chain) {
            std::cout << "[HTTP] " << req->methodString() << " " << req->path() 
                      << " from " << req->peerAddr().toIpPort() << std::endl;

            if (req->method() == Options) {
                auto resp = HttpResponse::newHttpResponse();
                std::string origin = req->getHeader("Origin");
                if (origin.empty()) origin = req->getHeader("origin");
                
                if (!origin.empty()) {
                    resp->addHeader("Access-Control-Allow-Origin", origin);
                    resp->addHeader("Access-Control-Allow-Credentials", "true");
                    resp->addHeader("Vary", "Origin");
                }
                
                resp->addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE");
                resp->addHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With, Origin, Accept");
                resp->addHeader("Access-Control-Max-Age", "3600");
                resp->setStatusCode(k200OK);
                resp->setBody("OK"); 
                cb(resp);
            } else {
                chain();
            }
        });

        // Post-Handling Advice to add CORS headers to all responses
        app().registerPostHandlingAdvice([](const HttpRequestPtr &req, const HttpResponsePtr &resp) {
            std::string origin = req->getHeader("Origin");
            if (origin.empty()) origin = req->getHeader("origin");
            
            if (!origin.empty()) {
                resp->addHeader("Access-Control-Allow-Origin", origin);
                resp->addHeader("Access-Control-Allow-Credentials", "true");
                resp->addHeader("Vary", "Origin");
            }
        });

        // --- 4. API Handlers ---

        app().registerHandler("/api/status", [](const HttpRequestPtr&, std::function<void(const HttpResponsePtr&)>&& callback) {
            auto resp = HttpResponse::newHttpResponse();
            resp->setContentTypeCode(CT_APPLICATION_JSON);
            if (g_sim) resp->setBody(nlohmann::json(g_sim->GetStatus()).dump());
            callback(resp);
        }, {drogon::Get});

        app().registerHandler("/api/prices", [](const HttpRequestPtr&, std::function<void(const HttpResponsePtr&)>&& callback) {
            auto resp = HttpResponse::newHttpResponse();
            resp->setContentTypeCode(CT_APPLICATION_JSON);
            if (g_sim) resp->setBody(nlohmann::json(g_sim->GetPrices()).dump());
            callback(resp);
        }, {drogon::Get});

        app().registerHandler("/api/config", [](const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& callback) {
            auto resp = HttpResponse::newHttpResponse();
            resp->setContentTypeCode(CT_APPLICATION_JSON);
            
            if (req->method() == drogon::Get) {
                if (g_sim) resp->setBody(nlohmann::json(g_sim->GetStatus().config).dump());
            } else if (req->method() == drogon::Post) {
                try {
                    auto body = nlohmann::json::parse(req->body());
                    if (g_sim) g_sim->UpdateConfig(body.get<simulator::Config>());
                    resp->setBody("{\"success\": true}");
                } catch (const std::exception& e) {
                    resp->setStatusCode(k400BadRequest);
                    resp->setBody("{\"error\": \"" + std::string(e.what()) + "\"}");
                }
            }
            callback(resp);
        }, {drogon::Get, drogon::Post});

        app().registerHandler("/api/start", [](const HttpRequestPtr&, std::function<void(const HttpResponsePtr&)>&& callback) {
            std::cout << "[API] Starting Simulator..." << std::endl;
            if (g_sim) g_sim->Start();
            auto resp = HttpResponse::newHttpResponse();
            resp->setContentTypeCode(CT_APPLICATION_JSON);
            resp->setBody("{\"success\": true}");
            callback(resp);
        }, {drogon::Post});

        app().registerHandler("/api/stop", [](const HttpRequestPtr&, std::function<void(const HttpResponsePtr&)>&& callback) {
            std::cout << "[API] Stopping Simulator..." << std::endl;
            if (g_sim) g_sim->Stop();
            auto resp = HttpResponse::newHttpResponse();
            resp->setContentTypeCode(CT_APPLICATION_JSON);
            resp->setBody("{\"success\": true}");
            callback(resp);
        }, {drogon::Post});

        // Health Checks
        auto health_handler = [](const HttpRequestPtr&, std::function<void(const HttpResponsePtr&)>&& callback) {
            auto resp = HttpResponse::newHttpResponse();
            resp->setBody("OK");
            callback(resp);
        };
        app().registerHandler("/", health_handler, {drogon::Get});
        app().registerHandler("/healthz", health_handler, {drogon::Get});

        // --- 5. Run Framework ---
        const char* port_env = std::getenv("PORT");
        uint16_t port = port_env ? static_cast<uint16_t>(std::stoi(port_env)) : 8080;

        std::cout << "Starting C++ Simulator Server (Drogon) on 0.0.0.0:" << port << "..." << std::endl;
        app().addListener("0.0.0.0", port)
             .setThreadNum(0) // Automatic based on cores
             .run();

    } catch (const std::exception& e) {
        std::cerr << "FATAL ERROR during startup: " << e.what() << std::endl;
        return 1;
    } catch (...) {
        std::cerr << "UNKNOWN FATAL ERROR during startup" << std::endl;
        return 1;
    }

    return 0;
}


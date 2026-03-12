#include "bigquery_client.hpp"
#include "pricing_message.pb.h"
#include <google/cloud/bigquery/storage/v1/bigquery_write_client.h>
#include <iostream>

namespace simulator {

namespace storage_v1 = ::google::cloud::bigquery::storage::v1;
namespace bigquery_storage_v1 = ::google::cloud::bigquery_storage_v1;

BigQueryClient::BigQueryClient(std::string project_id, std::string dataset_id, std::string table_id)
    : project_id_(std::move(project_id)), dataset_id_(std::move(dataset_id)), table_id_(std::move(table_id)) {
    
    table_name_ = "projects/" + project_id_ + "/datasets/" + dataset_id_ + "/tables/" + table_id_;
    
    auto options = google::cloud::Options{};
    client_ = std::make_shared<bigquery_storage_v1::BigQueryWriteClient>(
        bigquery_storage_v1::MakeBigQueryWriteConnection(options));
}

BigQueryClient::~BigQueryClient() {}

bool BigQueryClient::StreamMessages(const std::vector<PricingMessage>& messages) {
    if (messages.empty()) return true;

    storage_v1::AppendRowsRequest request;
    request.set_write_stream(table_name_ + "/streams/_default");
    
    auto* proto_rows = request.mutable_proto_rows();
    
    // Set the writer schema - this is required for the Storage Write API
    auto* writer_schema = proto_rows->mutable_writer_schema();
    PricingMessageProto::descriptor()->CopyTo(writer_schema->mutable_proto_descriptor());

    for (const auto& msg : messages) {
        PricingMessageProto proto_msg;
        proto_msg.set_symbol(msg.symbol);
        proto_msg.set_sequencenumber(msg.sequence_number);
        proto_msg.set_price(msg.price);
        proto_msg.set_currency(msg.currency);
        proto_msg.set_venue(msg.venue);
        proto_msg.set_timestamp(msg.timestamp);
        proto_msg.set_bidask(msg.bid_ask);
        proto_msg.set_quantity(msg.quantity);
        proto_msg.set_publishtime(msg.publish_time);
        
        proto_rows->mutable_rows()->add_serialized_rows(proto_msg.SerializeAsString());
    }

    // Use a unique trace_id for deduplication based on sequence numbers and current time to prevent collisions
    if (!messages.empty()) {
        auto now_ns = std::chrono::system_clock::now().time_since_epoch().count();
        std::string trace_id = "batch-" + std::to_string(messages.front().sequence_number) + "-" + std::to_string(now_ns);
        request.set_trace_id(trace_id);
    }
    
    try {
        std::cout << "[BigQuery] Opening stream to " << table_name_ << "..." << std::endl;
        
        // Create the bidirectional stream
        auto stream = client_->AsyncAppendRows();
        
        if (!stream) {
            std::cerr << "[BigQuery] Error: Failed to create BigQuery stream" << std::endl;
            return false;
        }

        // Start the stream
        if (!stream->Start().get()) {
            std::cerr << "[BigQuery] Error: Failed to start BigQuery stream" << std::endl;
            return false;
        }

        // Send the request
        std::cout << "[BigQuery] Sending " << messages.size() << " rows..." << std::endl;
        if (!stream->Write(request, grpc::WriteOptions()).get()) {
            std::cerr << "[BigQuery] Error: Failed to write to BigQuery stream" << std::endl;
            return false;
        }
    
        // Read the response
        auto response = stream->Read().get();
        if (!response) {
            auto status = stream->Finish().get();
            std::cerr << "[BigQuery] Error: Failed to read response from BigQuery stream: " << status.message() << " (code: " << (int)status.code() << ")" << std::endl;
            return false;
        }

        if (response->has_error()) {
            std::cerr << "[BigQuery] Error in response: " << response->error().message() << std::endl;
            return false;
        }

        // Close the stream
        if (!stream->WritesDone().get()) {
            std::cerr << "[BigQuery] Error: Failed to close BigQuery stream writes" << std::endl;
            return false;
        }

        auto status = stream->Finish().get();
        if (!status.ok()) {
            std::cerr << "[BigQuery] Error: BigQuery stream finished with error: " << status.message() << std::endl;
            return false;
        }

        std::cout << "[BigQuery] Successfully streamed " << messages.size() << " messages to " << table_name_ << std::endl;
        return true; 
    } catch (const std::exception& e) {
        std::cerr << "[BigQuery] Exception in StreamMessages: " << e.what() << std::endl;
        return false;
    }
}

bool BigQueryClient::StreamMessage(const PricingMessage& message) {
    return StreamMessages({message});
}

} // namespace simulator

#pragma once

#include "types.hpp"
#include <google/cloud/bigquery/storage/v1/bigquery_write_client.h>
#include <memory>
#include <vector>

namespace simulator {

class BigQueryClient {
public:
    BigQueryClient(std::string project_id, std::string dataset_id, std::string table_id);
    ~BigQueryClient();

    bool StreamMessages(const std::vector<PricingMessage>& messages);
    bool StreamMessage(const PricingMessage& message);

private:
    std::string project_id_;
    std::string dataset_id_;
    std::string table_id_;
    std::string table_name_;
    
    std::shared_ptr<google::cloud::bigquery_storage_v1::BigQueryWriteClient> client_;
};

} // namespace simulator

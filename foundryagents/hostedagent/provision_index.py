"""Minimal provisioner for the Contoso Outdoors RAG index.

Creates the search index (schema: id / content / sourceName / sourceLink with a
semantic configuration named "default") and uploads a few sample documents.

Uses Entra ID (DefaultAzureCredential) against the data plane, so the signed-in
identity needs a Search Index Data Contributor role on the target service.

Env vars:
  AZURE_SEARCH_ENDPOINT     e.g. https://aiservicesktdpsearch.search.windows.net
  AZURE_SEARCH_INDEX_NAME   defaults to "contoso-outdoors"
"""

import os

from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchableField,
    SearchIndex,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
    SimpleField,
    SearchFieldDataType,
)

ENDPOINT = os.environ["AZURE_SEARCH_ENDPOINT"]
INDEX_NAME = os.environ.get("AZURE_SEARCH_INDEX_NAME", "contoso-outdoors")

DOCUMENTS = [
    {
        "id": "1",
        "sourceName": "TrailMaster X4 Tent - Setup Guide",
        "content": (
            "The Contoso TrailMaster X4 is a 4-person, 3-season tent. To pitch it, "
            "unfold the tent body, insert the two colour-coded shock-corded poles into "
            "the matching sleeves, clip the canopy to the poles, then stake out the "
            "corners. Attach the rainfly with the buckle straps and tension the guy "
            "lines. Setup takes about 10 minutes for one person."
        ),
        "sourceLink": "https://contoso.example/docs/trailmaster-x4-setup",
    },
    {
        "id": "2",
        "sourceName": "Alpine Down Sleeping Bag - Care Instructions",
        "content": (
            "The Contoso Alpine down sleeping bag is rated to -7 degrees Celsius. "
            "Store it uncompressed in the supplied cotton sack to preserve loft. "
            "Machine wash on a gentle cycle with a down-specific detergent and tumble "
            "dry on low with a couple of clean tennis balls to restore fill. Never "
            "dry clean, as solvents strip the down of its natural oils."
        ),
        "sourceLink": "https://contoso.example/docs/alpine-sleeping-bag-care",
    },
    {
        "id": "3",
        "sourceName": "Contoso Outdoors - Returns and Warranty Policy",
        "content": (
            "Contoso Outdoors accepts returns of unused gear within 30 days of "
            "purchase for a full refund. Items must include original tags and "
            "packaging. Tents and sleeping bags carry a limited lifetime warranty "
            "against manufacturing defects. To start a return, use your order number "
            "on the returns portal and print the prepaid shipping label."
        ),
        "sourceLink": "https://contoso.example/docs/returns-warranty",
    },
]


def main() -> None:
    credential = DefaultAzureCredential()

    index_client = SearchIndexClient(endpoint=ENDPOINT, credential=credential)

    index = SearchIndex(
        name=INDEX_NAME,
        fields=[
            SimpleField(name="id", type=SearchFieldDataType.String, key=True),
            SearchableField(name="content", type=SearchFieldDataType.String),
            SearchableField(name="sourceName", type=SearchFieldDataType.String),
            SimpleField(name="sourceLink", type=SearchFieldDataType.String),
        ],
        semantic_search=SemanticSearch(
            configurations=[
                SemanticConfiguration(
                    name="default",
                    prioritized_fields=SemanticPrioritizedFields(
                        title_field=SemanticField(field_name="sourceName"),
                        content_fields=[SemanticField(field_name="content")],
                    ),
                )
            ]
        ),
    )

    index_client.create_or_update_index(index)
    print(f"Index '{INDEX_NAME}' created/updated on {ENDPOINT}")

    search_client = SearchClient(endpoint=ENDPOINT, index_name=INDEX_NAME, credential=credential)
    result = search_client.upload_documents(documents=DOCUMENTS)
    succeeded = sum(1 for r in result if r.succeeded)
    print(f"Uploaded {succeeded}/{len(DOCUMENTS)} documents")


if __name__ == "__main__":
    main()

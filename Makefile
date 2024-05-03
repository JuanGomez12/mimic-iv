#!make

SHELL := /bin/bash

BLUE="\033[00;94m"
GREEN="\033[00;92m"
RED="\033[00;31m"
RESTORE="\033[0m"
YELLOW="\033[00;93m"
CYAN="\e[0;96m"
GREY="\e[2:N"
SPACER="----------"

define setup_env
	$(eval ENV_FILE := .envs/$(1)/$(1).env)
	@@echo " - setup env $(ENV_FILE)"
	$(eval include .envs/$(1)/$(1).env)
	$(eval export sed 's/=.*//' .envs/$(1)/$(1).env)
endef

create_mlflow_bucket:
# To be run inside MinIO to create a bucket, or ignore if it already exists
	mc alias set s3 http://localhost:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
	mc mb s3/$AWS_S3_BUCKET_NAME --ignore-existing --region $MINIO_REGION

mlflow_bucket:
	source .env
	docker compose run --rm create_buckets

test_debug:
	conda run --no--capture--output -n test coverage run -m pytest
	conda run --no--capture--output -n test coverage html -d /app/test/coverage_report

coverage_report:
	@echo ${SPACER} Running unit tests... ${SPACER}
	docker compose run --rm test bash -c "make test_debug"

build_project_local:
	@echo ${SPACER} Building project locally ${SPACER}
	docker compose --env-file ./.envs/local/local.env build minio mlflow
	docker compose run --rm create_buckets
	@echo ${SPACER} Done ${SPACER}


build_mimic_database_local:
	@echo ${SPACER} Building mimic database locally ${SPACER}
	docker compose --env-file .envs/local/local.env --env-file .envs/mimic.env up -d data_postgresql_mimic
	docker compose --env-file .envs/local/local.env --env-file .envs/mimic.env exec -w /mimic data_postgresql_mimic  bash create_db.sh

remove_mimic_database_local:
	$(call setup_env,local)
	@echo ${SPACER} Removing local mimic database and named volume: ${MIMIC_POSTGRES_DB} ${SPACER}
	sleep 5
	docker compose rm -sf data_postgresql_mimic
	docker volume rm ${MIMIC_POSTGRES_DB}

rebuild_mimic_database_local:
	make remove_mimic_database_local
	make build_mimic_database_local

startup_project_local:
	@echo ${SPACER}  Building project locally ${SPACER}
	docker compose --env-file ./.envs/local/local.env up -d minio mlflow ml_model_api data_api
	docker compose --env-file ./.envs/local/local.env run --rm create_buckets
	# docker compose --env-file ./.envs/local/local.env run --rm data_api sh -c "conda run --no-capture-output -n fastapi python utils/database_initalization.py"
	@echo ${SPACER} Done ${SPACER}

run_ml_model_local:
	@echo ${SPACER}  Running ML model locally ${SPACER}
	docker compose --env-file ./.envs/local/local.env up ml_model_train_cpu
	@echo ${SPACER} Done ${SPACER}

deploy_local:
	cp /d/.dev/test_ds/DS_model/.envs/local/local.env .env
	make build_project_local
	make startup_project_local
	@echo ${SPACER} Wait 5 seconds for everything to be set up correctly... ${SPACER}
	sleep 5
	# make run_ml_model_local
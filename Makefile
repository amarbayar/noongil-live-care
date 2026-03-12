.PHONY: setup ios-build ios-test backend-dev backend-test contracts-gen lint config-push infra-plan infra-apply

setup:
	@echo "==> Installing dependencies..."
	which xcodegen || brew install xcodegen
	which swiftlint || brew install swiftlint
	which node || brew install node
	which terraform || brew install terraform
	cd contracts && npm install
	cd backend && npm install

ios-build:
	cd ios && ./build.sh

ios-test:
	cd ios && xcodebuild test \
		-target Noongil \
		-sdk iphonesimulator \
		-destination 'platform=iOS Simulator,name=iPhone 16' \
		SYMROOT=build

backend-dev:
	cd backend && npm run dev

backend-test:
	cd backend && npm test

contracts-gen:
	cd contracts && npx tsx codegen/swift-gen.ts
	cd contracts && npx tsx codegen/kotlin-gen.ts

lint:
	cd ios && swiftlint
	cd backend && npx eslint src/
	cd contracts && npx eslint src/

config-push:
	./infra/scripts/push-config.sh

infra-plan:
	cd infra/terraform && terraform plan

infra-apply:
	cd infra/terraform && terraform apply

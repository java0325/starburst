-- TPC-DS 스키마 전체 개요
-- 실행: ./trino --server http://localhost:8080 -f sql/00_schema_overview.sql

-- 사용 가능한 카탈로그 목록
SHOW CATALOGS;

-- tpcds 카탈로그 스키마 목록 (sf1, sf10, sf100 등 스케일팩터별)
SHOW SCHEMAS FROM tpcds;

-- sf1 스키마의 전체 테이블 목록 (24개)
SHOW TABLES FROM tpcds.sf1;

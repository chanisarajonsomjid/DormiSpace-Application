--
-- PostgreSQL database dump
--

\restrict DiNDcKWb1s0MYOSS6tEwyHvKtRSo44IK01AbQ7D4E2fZRHcA0f5ABjS7pWqXIa5

-- Dumped from database version 18.1
-- Dumped by pg_dump version 18.0

-- Started on 2026-01-16 22:04:29 +07

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 246 (class 1255 OID 25024)
-- Name: auto_calculate_bill_amounts(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.auto_calculate_bill_amounts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- คำนวณ Subtotal
    NEW."Subtotal" := COALESCE(NEW."Rent_Amount", 0)
                    + COALESCE(NEW."Water_Amount", 0)
                    + COALESCE(NEW."Electricity_Amount", 0)
                    + COALESCE(NEW."Other_Charges", 0)
                    - COALESCE(NEW."Discount", 0);
    
    -- คำนวณ Total_Amount
    NEW."Total_Amount" := NEW."Subtotal" + COALESCE(NEW."Late_Fee", 0);
    
    -- Warning ถ้าเป็น 0
    IF NEW."Total_Amount" <= 0 THEN
        RAISE WARNING 'Total amount is zero or negative for Bill_ID %', NEW."Bill_ID";
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.auto_calculate_bill_amounts() OWNER TO postgres;

--
-- TOC entry 245 (class 1255 OID 16885)
-- Name: calculate_bill_subtotal(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_bill_subtotal() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW."Subtotal" := COALESCE(NEW."Rent_Amount", 0) 
                    + COALESCE(NEW."Water_Amount", 0)
                    + COALESCE(NEW."Electricity_Amount", 0)
                    + COALESCE(NEW."Other_Charges", 0)
                    - COALESCE(NEW."Discount", 0);
    
    NEW."Total_Amount" := NEW."Subtotal" + COALESCE(NEW."Late_Fee", 0);
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.calculate_bill_subtotal() OWNER TO postgres;

--
-- TOC entry 260 (class 1255 OID 16891)
-- Name: calculate_late_fee(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_late_fee() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    days_late INTEGER;
    late_fee_per_day NUMERIC := 50.00; -- ค่าปรับวันละ 50 บาท
BEGIN
    IF NEW."Payment_Status" = 'Overdue' THEN

        -- DATE - DATE = INTEGER (จำนวนวัน)
        days_late := CURRENT_DATE - NEW."Due_Date";

        IF days_late > 0 THEN
            NEW."Late_Fee" := days_late * late_fee_per_day;
        ELSE
            NEW."Late_Fee" := 0;
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.calculate_late_fee() OWNER TO postgres;

--
-- TOC entry 262 (class 1255 OID 25316)
-- Name: check_landlord_role(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_landlord_role() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM "User_Account"
        WHERE "User_ID" = NEW."User_ID"
        AND "Role" = 'Landlord'
    ) THEN
        RAISE EXCEPTION 'User_ID % is not a Landlord', NEW."User_ID";
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_landlord_role() OWNER TO postgres;

--
-- TOC entry 253 (class 1255 OID 25070)
-- Name: generate_receipt_number(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_receipt_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    receipt_date DATE;
BEGIN
    IF NEW."Payment_Status" = 'Paid'
       AND OLD."Payment_Status" IS DISTINCT FROM 'Paid' THEN

        -- แปลงจาก TIMESTAMP → DATE อย่างถูกต้อง
        receipt_date := COALESCE(NEW."Payment_Date", CURRENT_TIMESTAMP)::DATE;

        NEW."Receipt_Date" := receipt_date;

        NEW."Receipt_Number" :=
            'RCP-' ||
            TO_CHAR(receipt_date, 'YYYYMMDD') || '-' ||
            LPAD(NEW."Bill_ID"::TEXT, 6, '0');
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.generate_receipt_number() OWNER TO postgres;

--
-- TOC entry 247 (class 1255 OID 16887)
-- Name: update_modified_timestamp(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_modified_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW."Updated_At" = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_modified_timestamp() OWNER TO postgres;

--
-- TOC entry 248 (class 1255 OID 25027)
-- Name: validate_payment_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_payment_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- ถ้า status = Paid ต้องมี Payment_Date และ Payment_Method
    IF NEW."Payment_Status" = 'Paid' THEN
        IF NEW."Payment_Date" IS NULL THEN
            RAISE EXCEPTION 'Payment_Date is required when status is Paid';
        END IF;
        IF NEW."Payment_Method" IS NULL THEN
            RAISE EXCEPTION 'Payment_Method is required when status is Paid';
        END IF;
    END IF;
    
    -- ถ้า status = Pending ไม่ควรมี Payment_Date
    IF NEW."Payment_Status" = 'Pending' THEN
        NEW."Payment_Date" := NULL;
        NEW."Payment_Method" := NULL;
        NEW."Receipt_Date" := NULL;
        NEW."Receipt_Number" := NULL;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validate_payment_status() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 224 (class 1259 OID 16500)
-- Name: Apartment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Apartment" (
    "Apartment_ID" integer NOT NULL,
    "Landlord_ID" integer,
    "A_Name" character varying(100) NOT NULL,
    "A_Address" text NOT NULL,
    "A_District" character varying(50) NOT NULL,
    "A_Province" character varying(50) NOT NULL,
    "A_Postcode" character varying(10) NOT NULL,
    "A_City" character varying(50) NOT NULL,
    "A_TotalRoom" integer NOT NULL,
    "A_PhoneNum" character varying(20) NOT NULL
);


ALTER TABLE public."Apartment" OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 16499)
-- Name: Apartment_Apartment_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Apartment_Apartment_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Apartment_Apartment_ID_seq" OWNER TO postgres;

--
-- TOC entry 4019 (class 0 OID 0)
-- Dependencies: 223
-- Name: Apartment_Apartment_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Apartment_Apartment_ID_seq" OWNED BY public."Apartment"."Apartment_ID";


--
-- TOC entry 232 (class 1259 OID 16597)
-- Name: Bank_Account; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Bank_Account" (
    "Bank_ID" integer NOT NULL,
    "Landlord_ID" integer NOT NULL,
    "B_Name" character varying(100) NOT NULL,
    "B_Number" character varying(50) NOT NULL
);


ALTER TABLE public."Bank_Account" OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 16596)
-- Name: Bank_Account_Bank_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Bank_Account_Bank_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Bank_Account_Bank_ID_seq" OWNER TO postgres;

--
-- TOC entry 4020 (class 0 OID 0)
-- Dependencies: 231
-- Name: Bank_Account_Bank_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Bank_Account_Bank_ID_seq" OWNED BY public."Bank_Account"."Bank_ID";


--
-- TOC entry 244 (class 1259 OID 25531)
-- Name: Bill_Payment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Bill_Payment" (
    "Bill_ID" integer NOT NULL,
    "Apartment_ID" integer NOT NULL,
    "Room_ID" integer NOT NULL,
    "User_ID" integer NOT NULL,
    "Contract_ID" integer NOT NULL,
    "Created_Date" date NOT NULL,
    "Due_Date" date NOT NULL,
    "Payment_Date" date,
    "Receipt_Date" date,
    "Subtotal" numeric(10,2) NOT NULL,
    "Late_Fee" numeric(10,2) DEFAULT 0,
    "Total_Amount" numeric(10,2) NOT NULL,
    "Payment_Status" character varying(20) NOT NULL,
    "Payment_Method" character varying(30),
    "Created_At" timestamp without time zone DEFAULT now()
);


ALTER TABLE public."Bill_Payment" OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 25530)
-- Name: Bill_Payment_Bill_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Bill_Payment_Bill_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Bill_Payment_Bill_ID_seq" OWNER TO postgres;

--
-- TOC entry 4021 (class 0 OID 0)
-- Dependencies: 243
-- Name: Bill_Payment_Bill_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Bill_Payment_Bill_ID_seq" OWNED BY public."Bill_Payment"."Bill_ID";


--
-- TOC entry 238 (class 1259 OID 16642)
-- Name: Electricity_Meter; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Electricity_Meter" (
    "Meter_ID" integer NOT NULL,
    "Room_ID" integer NOT NULL,
    "readingDate" date,
    "currentRead" integer,
    "previousRead" integer,
    "collectedElecImage" text,
    "usedElecUnit" integer GENERATED ALWAYS AS (("currentRead" - "previousRead")) STORED,
    CONSTRAINT check_elec_reading CHECK (("currentRead" >= "previousRead"))
);


ALTER TABLE public."Electricity_Meter" OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 16641)
-- Name: Electricity_Meter_Meter_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Electricity_Meter_Meter_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Electricity_Meter_Meter_ID_seq" OWNER TO postgres;

--
-- TOC entry 4022 (class 0 OID 0)
-- Dependencies: 237
-- Name: Electricity_Meter_Meter_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Electricity_Meter_Meter_ID_seq" OWNED BY public."Electricity_Meter"."Meter_ID";


--
-- TOC entry 234 (class 1259 OID 16611)
-- Name: Fixed_Cost; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Fixed_Cost" (
    "FixedCost_ID" integer NOT NULL,
    "Apartment_ID" integer NOT NULL,
    "FixedcostName" character varying(100),
    "FixedcostPrice" numeric(10,2),
    "Unit" character varying(20),
    "FixedcostType" character varying(50),
    "Charge_Method" character varying(30),
    "Applies_To" character varying(30),
    "Is_Metered" boolean DEFAULT false,
    CONSTRAINT chk_applies_to CHECK ((("Applies_To")::text = ANY ((ARRAY['Room'::character varying, 'Bill'::character varying, 'Contract'::character varying])::text[]))),
    CONSTRAINT chk_charge_method CHECK ((("Charge_Method")::text = ANY ((ARRAY['Per Unit'::character varying, 'Per Month'::character varying, 'Per Day'::character varying, 'Flat'::character varying])::text[])))
);


ALTER TABLE public."Fixed_Cost" OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 16610)
-- Name: Fixed_Cost_FixedCost_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Fixed_Cost_FixedCost_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Fixed_Cost_FixedCost_ID_seq" OWNER TO postgres;

--
-- TOC entry 4023 (class 0 OID 0)
-- Dependencies: 233
-- Name: Fixed_Cost_FixedCost_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Fixed_Cost_FixedCost_ID_seq" OWNED BY public."Fixed_Cost"."FixedCost_ID";


--
-- TOC entry 226 (class 1259 OID 16523)
-- Name: Floor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Floor" (
    "Floor_ID" integer NOT NULL,
    "Apartment_ID" integer,
    "Floor_Number" integer NOT NULL,
    "Room_Total" integer NOT NULL
);


ALTER TABLE public."Floor" OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16522)
-- Name: Floor_Floor_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Floor_Floor_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Floor_Floor_ID_seq" OWNER TO postgres;

--
-- TOC entry 4024 (class 0 OID 0)
-- Dependencies: 225
-- Name: Floor_Floor_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Floor_Floor_ID_seq" OWNED BY public."Floor"."Floor_ID";


--
-- TOC entry 222 (class 1259 OID 16481)
-- Name: Landlord; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Landlord" (
    "Landlord_ID" integer NOT NULL,
    "User_ID" integer NOT NULL,
    "L_FirstName" character varying(50) NOT NULL,
    "L_LastName" character varying(50) NOT NULL,
    "L_PhoneNum" character varying(20) NOT NULL,
    "L_Email" character varying(50) NOT NULL
);


ALTER TABLE public."Landlord" OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16480)
-- Name: Landlord_Landlord_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Landlord_Landlord_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Landlord_Landlord_ID_seq" OWNER TO postgres;

--
-- TOC entry 4025 (class 0 OID 0)
-- Dependencies: 221
-- Name: Landlord_Landlord_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Landlord_Landlord_ID_seq" OWNED BY public."Landlord"."Landlord_ID";


--
-- TOC entry 242 (class 1259 OID 16720)
-- Name: Maintenance_Request; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Maintenance_Request" (
    "Request_ID" integer NOT NULL,
    "Room_ID" integer NOT NULL,
    "User_ID" integer NOT NULL,
    "Apartment_ID" integer,
    "M_Title" character varying(100) NOT NULL,
    "M_Description" text,
    "M_Status" character varying(20) DEFAULT 'Pending'::character varying NOT NULL,
    "Maintenance_Provider" character varying(100),
    "Maintenance_Expense" numeric(10,2),
    "Notes" text,
    "Note" text,
    "Created_Date" date,
    CONSTRAINT check_maintenance_status CHECK ((("M_Status")::text = ANY ((ARRAY['Pending'::character varying, 'In_Progress'::character varying, 'Completed'::character varying])::text[])))
);


ALTER TABLE public."Maintenance_Request" OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 16719)
-- Name: Maintenance_Request_Request_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Maintenance_Request_Request_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Maintenance_Request_Request_ID_seq" OWNER TO postgres;

--
-- TOC entry 4026 (class 0 OID 0)
-- Dependencies: 241
-- Name: Maintenance_Request_Request_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Maintenance_Request_Request_ID_seq" OWNED BY public."Maintenance_Request"."Request_ID";


--
-- TOC entry 240 (class 1259 OID 16693)
-- Name: Notification; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Notification" (
    "Notification_ID" integer NOT NULL,
    "Receiver_User_ID" integer NOT NULL,
    "Sender_User_ID" integer,
    "Notification_Type" character varying(50) NOT NULL,
    "Notification_Header" character varying(100) NOT NULL,
    "Notification_Message" text,
    "Is_Read" boolean DEFAULT false,
    "Created_At" time with time zone DEFAULT CURRENT_TIMESTAMP,
    "Sent_At" time with time zone,
    CONSTRAINT chk_sender_receiver CHECK ((("Sender_User_ID" IS NULL) OR ("Sender_User_ID" <> "Receiver_User_ID")))
);


ALTER TABLE public."Notification" OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 16692)
-- Name: Notification_Notification_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Notification_Notification_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Notification_Notification_ID_seq" OWNER TO postgres;

--
-- TOC entry 4027 (class 0 OID 0)
-- Dependencies: 239
-- Name: Notification_Notification_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Notification_Notification_ID_seq" OWNED BY public."Notification"."Notification_ID";


--
-- TOC entry 228 (class 1259 OID 16536)
-- Name: Room; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Room" (
    "Room_ID" integer NOT NULL,
    "Apartment_ID" integer,
    "Floor_ID" integer,
    "R_Number" character varying(10) NOT NULL,
    "R_Type" character varying(50) NOT NULL,
    "R_Status" character varying(20) NOT NULL,
    "R_Price" numeric(10,2) NOT NULL,
    "R_Detail" text
);


ALTER TABLE public."Room" OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 16535)
-- Name: Room_Room_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Room_Room_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Room_Room_ID_seq" OWNER TO postgres;

--
-- TOC entry 4028 (class 0 OID 0)
-- Dependencies: 227
-- Name: Room_Room_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Room_Room_ID_seq" OWNED BY public."Room"."Room_ID";


--
-- TOC entry 230 (class 1259 OID 16560)
-- Name: Tenant_Contract_Detail; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Tenant_Contract_Detail" (
    "Contract_ID" integer NOT NULL,
    "User_ID" integer,
    "Room_ID" integer,
    "C_FirstName" character varying(50) NOT NULL,
    "C_LastName" character varying(50) NOT NULL,
    "C_Address" text NOT NULL,
    "C_Email" character varying(50) NOT NULL,
    "C_PhoneNum" character varying(20) NOT NULL,
    "C_RentalRate" numeric(10,2),
    "C_DepositAmount" numeric(10,2),
    "C_Type" character varying(20),
    "C_Status" character varying(20),
    "C_StartDate" date,
    "C_EndDate" date,
    "C_pdf_with_signature" text,
    signature_tenant text,
    signature_landlord text,
    signature_witness1 text,
    signature_witness2 text
);


ALTER TABLE public."Tenant_Contract_Detail" OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 16559)
-- Name: Tenant_Contract_Detail_Contract_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Tenant_Contract_Detail_Contract_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Tenant_Contract_Detail_Contract_ID_seq" OWNER TO postgres;

--
-- TOC entry 4029 (class 0 OID 0)
-- Dependencies: 229
-- Name: Tenant_Contract_Detail_Contract_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Tenant_Contract_Detail_Contract_ID_seq" OWNED BY public."Tenant_Contract_Detail"."Contract_ID";


--
-- TOC entry 220 (class 1259 OID 16469)
-- Name: User_Account; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."User_Account" (
    "User_ID" integer NOT NULL,
    "Email" character varying(50) CONSTRAINT "User_Account_Username_not_null" NOT NULL,
    "Account_Status" character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    "Role" character varying(20) NOT NULL,
    "Firebase_UID" character varying(128) NOT NULL,
    "Created_At" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "check_Account_Status" CHECK ((("Account_Status")::text = ANY ((ARRAY['Active'::character varying, 'Inactive'::character varying])::text[]))),
    CONSTRAINT "check_Role" CHECK ((("Role")::text = ANY ((ARRAY['Landlord'::character varying, 'Tenant'::character varying])::text[])))
);


ALTER TABLE public."User_Account" OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 16468)
-- Name: User_Account_User_ID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."User_Account_User_ID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."User_Account_User_ID_seq" OWNER TO postgres;

--
-- TOC entry 4030 (class 0 OID 0)
-- Dependencies: 219
-- Name: User_Account_User_ID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."User_Account_User_ID_seq" OWNED BY public."User_Account"."User_ID";


--
-- TOC entry 236 (class 1259 OID 16626)
-- Name: Water_Meter; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Water_Meter" (
    "Meter_WaterID" integer NOT NULL,
    "Room_ID" integer NOT NULL,
    "RecordedDate" date,
    "currentRead" integer,
    "previousRead" integer,
    "collectedWaterImage" text,
    "usedWaterUnit" integer GENERATED ALWAYS AS (("currentRead" - "previousRead")) STORED,
    CONSTRAINT check_water_reading CHECK (("currentRead" >= "previousRead"))
);


ALTER TABLE public."Water_Meter" OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 16625)
-- Name: Water_Meter_Meter_WaterID_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Water_Meter_Meter_WaterID_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Water_Meter_Meter_WaterID_seq" OWNER TO postgres;

--
-- TOC entry 4031 (class 0 OID 0)
-- Dependencies: 235
-- Name: Water_Meter_Meter_WaterID_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Water_Meter_Meter_WaterID_seq" OWNED BY public."Water_Meter"."Meter_WaterID";


--
-- TOC entry 3741 (class 2604 OID 16503)
-- Name: Apartment Apartment_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Apartment" ALTER COLUMN "Apartment_ID" SET DEFAULT nextval('public."Apartment_Apartment_ID_seq"'::regclass);


--
-- TOC entry 3745 (class 2604 OID 16600)
-- Name: Bank_Account Bank_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Bank_Account" ALTER COLUMN "Bank_ID" SET DEFAULT nextval('public."Bank_Account_Bank_ID_seq"'::regclass);


--
-- TOC entry 3757 (class 2604 OID 25534)
-- Name: Bill_Payment Bill_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Bill_Payment" ALTER COLUMN "Bill_ID" SET DEFAULT nextval('public."Bill_Payment_Bill_ID_seq"'::regclass);


--
-- TOC entry 3750 (class 2604 OID 16645)
-- Name: Electricity_Meter Meter_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Electricity_Meter" ALTER COLUMN "Meter_ID" SET DEFAULT nextval('public."Electricity_Meter_Meter_ID_seq"'::regclass);


--
-- TOC entry 3746 (class 2604 OID 16614)
-- Name: Fixed_Cost FixedCost_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Fixed_Cost" ALTER COLUMN "FixedCost_ID" SET DEFAULT nextval('public."Fixed_Cost_FixedCost_ID_seq"'::regclass);


--
-- TOC entry 3742 (class 2604 OID 16526)
-- Name: Floor Floor_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Floor" ALTER COLUMN "Floor_ID" SET DEFAULT nextval('public."Floor_Floor_ID_seq"'::regclass);


--
-- TOC entry 3740 (class 2604 OID 16484)
-- Name: Landlord Landlord_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Landlord" ALTER COLUMN "Landlord_ID" SET DEFAULT nextval('public."Landlord_Landlord_ID_seq"'::regclass);


--
-- TOC entry 3755 (class 2604 OID 16723)
-- Name: Maintenance_Request Request_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Maintenance_Request" ALTER COLUMN "Request_ID" SET DEFAULT nextval('public."Maintenance_Request_Request_ID_seq"'::regclass);


--
-- TOC entry 3752 (class 2604 OID 16696)
-- Name: Notification Notification_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Notification" ALTER COLUMN "Notification_ID" SET DEFAULT nextval('public."Notification_Notification_ID_seq"'::regclass);


--
-- TOC entry 3743 (class 2604 OID 16539)
-- Name: Room Room_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Room" ALTER COLUMN "Room_ID" SET DEFAULT nextval('public."Room_Room_ID_seq"'::regclass);


--
-- TOC entry 3744 (class 2604 OID 16563)
-- Name: Tenant_Contract_Detail Contract_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Tenant_Contract_Detail" ALTER COLUMN "Contract_ID" SET DEFAULT nextval('public."Tenant_Contract_Detail_Contract_ID_seq"'::regclass);


--
-- TOC entry 3737 (class 2604 OID 16472)
-- Name: User_Account User_ID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."User_Account" ALTER COLUMN "User_ID" SET DEFAULT nextval('public."User_Account_User_ID_seq"'::regclass);


--
-- TOC entry 3748 (class 2604 OID 16629)
-- Name: Water_Meter Meter_WaterID; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Water_Meter" ALTER COLUMN "Meter_WaterID" SET DEFAULT nextval('public."Water_Meter_Meter_WaterID_seq"'::regclass);


--
-- TOC entry 3993 (class 0 OID 16500)
-- Dependencies: 224
-- Data for Name: Apartment; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Apartment" ("Apartment_ID", "Landlord_ID", "A_Name", "A_Address", "A_District", "A_Province", "A_Postcode", "A_City", "A_TotalRoom", "A_PhoneNum") FROM stdin;
1	1	Moonlight Dorm	999 Phutthamonthon Sai 4	Phutthamonthon	Nakhon Pathom	73170	Salaya	20	02-333-4444
2	2	Lalisa House	45 Rattanathibet Rd	Mueang	Nonthaburi	11000	Nonthaburi	30	02-555-6666
3	3	Rose Garden Apt	88 Sukhumvit Soi 24	Khlong Toei	Bangkok	10110	Bangkok	40	02-777-8888
4	4	Ruby Court	55 Thong Lo Rd	Watthana	Bangkok	10110	Bangkok	50	02-999-0000
5	5	Sooya Mansion	101 Phaya Thai Rd	Ratchathewi	Bangkok	10400	Bangkok	60	02-123-1234
6	6	Kenlo Living	20 Asoke Montri Rd	Watthana	Bangkok	10110	Bangkok	70	02-456-4567
7	7	Skyline Dorm	9 Rama I Rd	Pathum Wan	Bangkok	10330	Bangkok	80	02-789-7890
8	8	Hadid Heights	33 Silom Rd	Bang Rak	Bangkok	10500	Bangkok	90	02-321-6543
9	9	Model Manor	77 Sathorn Tai Rd	Sathorn	Bangkok	10120	Bangkok	100	02-654-9870
10	10	Z-Side Apartment	1 Nimmanhaemin Rd	Mueang	Chiang Mai	50200	Chiang Mai	110	053-111-222
\.


--
-- TOC entry 4001 (class 0 OID 16597)
-- Dependencies: 232
-- Data for Name: Bank_Account; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Bank_Account" ("Bank_ID", "Landlord_ID", "B_Name", "B_Number") FROM stdin;
1	1	Kasikorn Bank (KBank)	012-3-45678-9
2	2	SCB (Siam Commercial Bank)	987-6-54321-0
3	3	Bangkok Bank (BBL)	111-2-33344-5
4	4	Krungthai Bank (KTB)	555-6-77788-9
5	5	Kasikorn Bank (KBank)	999-8-77766-5
6	6	TTB (TMBThanachart)	444-3-22211-0
7	7	SCB (Siam Commercial Bank)	222-3-44455-6
8	8	Krungsri Bank (BAY)	777-1-23456-7
9	9	Bangkok Bank (BBL)	888-9-00011-2
10	10	UOB	333-2-11100-9
\.


--
-- TOC entry 4013 (class 0 OID 25531)
-- Dependencies: 244
-- Data for Name: Bill_Payment; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Bill_Payment" ("Bill_ID", "Apartment_ID", "Room_ID", "User_ID", "Contract_ID", "Created_Date", "Due_Date", "Payment_Date", "Receipt_Date", "Subtotal", "Late_Fee", "Total_Amount", "Payment_Status", "Payment_Method", "Created_At") FROM stdin;
1	1	1	1	1	2024-12-26	2025-01-05	\N	\N	6120.00	0.00	6120.00	Unpaid	\N	2026-01-13 13:56:58.988433
2	2	8	2	2	2024-12-26	2025-01-05	2024-12-30	2024-12-30	8190.00	0.00	8190.00	Paid	Transfer	2026-01-13 13:56:58.988433
3	3	11	3	3	2024-12-26	2025-01-05	\N	\N	8436.00	0.00	8436.00	Unpaid	\N	2026-01-13 13:56:58.988433
4	1	5	4	4	2024-12-26	2025-01-05	2025-01-07	2025-01-07	6450.00	200.00	6650.00	Paid	PromptPay	2026-01-13 13:56:58.988433
5	2	9	5	5	2024-12-26	2025-01-05	2025-01-08	2025-01-08	9650.00	450.00	10100.00	Paid	Transfer	2026-01-13 13:56:58.988433
\.


--
-- TOC entry 4007 (class 0 OID 16642)
-- Dependencies: 238
-- Data for Name: Electricity_Meter; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Electricity_Meter" ("Meter_ID", "Room_ID", "readingDate", "currentRead", "previousRead", "collectedElecImage") FROM stdin;
1	1	2024-12-25	4650	4500	elec_img_101.jpg
2	5	2024-12-25	1280	1200	elec_img_202.jpg
3	8	2024-12-25	3200	3000	elec_img_lalisa_201.jpg
4	9	2024-12-25	5850	5500	elec_img_lalisa_202.jpg
5	11	2024-12-25	290	200	elec_img_rose_101.jpg
\.


--
-- TOC entry 4003 (class 0 OID 16611)
-- Dependencies: 234
-- Data for Name: Fixed_Cost; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Fixed_Cost" ("FixedCost_ID", "Apartment_ID", "FixedcostName", "FixedcostPrice", "Unit", "FixedcostType", "Charge_Method", "Applies_To", "Is_Metered") FROM stdin;
1	1	Water Rate	18.00	Per Unit	Utility	Per Unit	Room	t
2	1	Electricity Rate	7.00	Per Unit	Utility	Per Unit	Room	t
3	1	High Speed Internet	300.00	Per Month	Internet	Per Month	Room	f
4	1	Late Payment Fee	100.00	Per Day	Late Fee	Per Day	Bill	f
5	2	Water Rate	20.00	Per Unit	Utility	Per Unit	Room	t
6	2	Electricity Rate	8.00	Per Unit	Utility	Per Unit	Room	t
7	2	WiFi 5G	350.00	Per Month	Internet	Per Month	Room	f
8	2	Late Payment Fee	150.00	Per Day	Late Fee	Per Day	Bill	f
9	3	Water Rate	17.00	Per Unit	Utility	Per Unit	Room	t
10	3	Electricity Rate	7.00	Per Unit	Utility	Per Unit	Room	t
11	3	Late Payment Fee	200.00	Per Day	Late Fee	Per Day	Bill	f
12	4	Water Rate	18.00	Per Unit	Utility	Per Unit	Room	t
13	4	Electricity Rate	8.00	Per Unit	Utility	Per Unit	Room	t
14	4	TV Rental	500.00	Per Month	Furniture	Per Month	Room	f
15	4	Late Payment Fee	100.00	Per Day	Late Fee	Per Day	Bill	f
\.


--
-- TOC entry 3995 (class 0 OID 16523)
-- Dependencies: 226
-- Data for Name: Floor; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Floor" ("Floor_ID", "Apartment_ID", "Floor_Number", "Room_Total") FROM stdin;
1	1	1	10
2	1	2	10
3	2	1	10
4	2	2	10
5	2	3	10
6	3	1	10
7	3	2	10
8	3	3	10
9	3	4	10
10	4	1	10
11	4	2	10
12	4	3	10
13	4	4	10
14	4	5	10
15	5	1	10
16	5	2	10
17	5	3	10
18	5	4	10
19	5	5	10
20	5	6	10
21	6	1	10
22	6	2	10
23	6	3	10
24	6	4	10
25	6	5	10
26	6	6	10
27	6	7	10
28	7	1	10
29	7	2	10
30	7	3	10
31	7	4	10
32	7	5	10
33	7	6	10
34	7	7	10
35	7	8	10
36	8	1	10
37	8	2	10
38	8	3	10
39	8	4	10
40	8	5	10
41	8	6	10
42	8	7	10
43	8	8	10
44	8	9	10
45	9	1	10
46	9	2	10
47	9	3	10
48	9	4	10
49	9	5	10
50	9	6	10
51	9	7	10
52	9	8	10
53	9	9	10
54	9	10	10
55	10	1	10
56	10	2	10
57	10	3	10
58	10	4	10
59	10	5	10
60	10	6	10
61	10	7	10
62	10	8	10
63	10	9	10
64	10	10	10
65	10	11	10
\.


--
-- TOC entry 3991 (class 0 OID 16481)
-- Dependencies: 222
-- Data for Name: Landlord; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Landlord" ("Landlord_ID", "User_ID", "L_FirstName", "L_LastName", "L_PhoneNum", "L_Email") FROM stdin;
1	11	Elle	Faning	0812345678	elle@gmail.com
2	12	Lalisa	Manoan	0881834422	Lalisa@gmail.com
3	13	Rosie	Park	0675554321	Rosie@gmail.com
4	14	Jennie	Kim	0996451423	Jennie@gmail.com
5	15	Jisoo	Kim	0654567713	Jisoo@gmail.com
6	16	Kendall	Jenner	0863454432	Kendall@gmail.com
7	17	Kylie	Jenner	0997453642	Kylie@gmail.com
8	18	Bella	Hadid	0675544231	Bella@gmail.com
9	19	Gigi	Hadid	0960811833	Gigi@gmail.com
10	20	Zayn	Malik	0658881616	Zayn@gmail.com
\.


--
-- TOC entry 4011 (class 0 OID 16720)
-- Dependencies: 242
-- Data for Name: Maintenance_Request; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Maintenance_Request" ("Request_ID", "Room_ID", "User_ID", "Apartment_ID", "M_Title", "M_Description", "M_Status", "Maintenance_Provider", "Maintenance_Expense", "Notes", "Note", "Created_Date") FROM stdin;
4	1	1	1	Air conditioner not cooling	The air conditioner is running but not cooling properly.	Pending	\N	\N	\N	Waiting for landlord review	2024-12-20
5	8	2	2	Water leakage in bathroom	Water is leaking from the sink pipe under the bathroom.	Pending	ABC Plumbing Service	1200.00	\N	Technician scheduled on 19 Dec	2024-12-18
6	11	3	3	Flickering lights	Ceiling lights flicker occasionally at night.	Completed	Bright Electric Co., Ltd.	800.00	\N	Replaced wiring and light switch	2024-12-15
7	5	4	1	Broken door lock	The door lock is loose and cannot be locked securely.	Completed	Secure Home Repair	500.00	\N	Lock replaced successfully	2024-12-10
8	9	5	2	No water supply	No water coming out from taps since morning.	Pending	\N	\N	\N	Urgent issue	2024-12-22
\.


--
-- TOC entry 4009 (class 0 OID 16693)
-- Dependencies: 240
-- Data for Name: Notification; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Notification" ("Notification_ID", "Receiver_User_ID", "Sender_User_ID", "Notification_Type", "Notification_Header", "Notification_Message", "Is_Read", "Created_At", "Sent_At") FROM stdin;
1	11	1	Maintenance Request	New Maintenance Request Submitted	Tenant Nick has submitted a maintenance request regarding air conditioner issue in Room 101.	f	14:40:27.147023+07	14:40:27.147023+07
2	12	5	Payment Confirmation	Payment Proof Submitted	Tenant Elsa has submitted payment proof for the December 2024 rental bill.	f	14:40:27.147023+07	14:40:27.147023+07
3	13	\N	Payment Notification	Tenant Payment Overdue	Tenant Gary has an overdue rental payment for December 2024.	f	14:40:27.147023+07	14:40:27.147023+07
4	1	\N	Rent Payment Due	Rental Payment Due Soon	Your rental payment for December 2024 is due on 5 January 2025.	f	14:40:27.147023+07	14:40:27.147023+07
5	2	12	Maintenance Update	Maintenance In Progress	Your maintenance request regarding water leakage is currently being handled.	f	14:40:27.147023+07	14:40:27.147023+07
6	3	\N	Lease Expiry Reminder	Lease Expiring Soon	Your lease agreement will expire within the next 30 days. Please contact the landlord for renewal.	f	14:40:27.147023+07	14:40:27.147023+07
\.


--
-- TOC entry 3997 (class 0 OID 16536)
-- Dependencies: 228
-- Data for Name: Room; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Room" ("Room_ID", "Apartment_ID", "Floor_ID", "R_Number", "R_Type", "R_Status", "R_Price", "R_Detail") FROM stdin;
1	1	1	101	Standard	Occupied	4500.00	Air-con, Single Bed
2	1	1	102	Standard	Available	4500.00	Air-con, Single Bed
3	1	1	103	Standard	Available	4500.00	Air-con, Single Bed
4	1	2	201	Deluxe	Available	5500.00	Air-con, Double Bed, TV
5	1	2	202	Deluxe	Occupied	5500.00	Air-con, Double Bed, TV
6	2	3	101	Studio	Available	6000.00	Fully Furnished
7	2	3	102	Studio	Available	6000.00	Fully Furnished
8	2	4	201	Studio	Occupied	6000.00	Fully Furnished
9	2	4	202	Studio	Occupied	6000.00	Fully Furnished
10	2	5	301	Suite	Available	8000.00	City View, Bathtub
11	3	6	101	Standard	Occupied	7500.00	Garden View
12	3	6	102	Standard	Occupied	7500.00	Garden View
13	3	7	201	Standard	Available	7500.00	Garden View
14	3	8	301	Deluxe	Available	9000.00	Corner Room
15	3	9	401	Penthouse	Available	12000.00	Top Floor, 2 Bedrooms
\.


--
-- TOC entry 3999 (class 0 OID 16560)
-- Dependencies: 230
-- Data for Name: Tenant_Contract_Detail; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Tenant_Contract_Detail" ("Contract_ID", "User_ID", "Room_ID", "C_FirstName", "C_LastName", "C_Address", "C_Email", "C_PhoneNum", "C_RentalRate", "C_DepositAmount", "C_Type", "C_Status", "C_StartDate", "C_EndDate", "C_pdf_with_signature", signature_tenant, signature_landlord, signature_witness1, signature_witness2) FROM stdin;
1	1	1	Nick	Wilde	123 Fox Burrow, Zootopia	nick_w@gmail.com	0811111111	4500.00	9000.00	1 Year	Active	2024-01-01	2025-01-01	contract_nick.pdf	sig_nick_w	sig_elle	sig_witness1	\N
2	2	8	Judy	Hopps	456 Carrot Farm, Bunnyburrow	judy_h@gmail.com	0822222222	6000.00	12000.00	1 Year	Active	2024-02-15	2025-02-15	contract_judy.pdf	sig_judy	sig_lalisa	\N	\N
3	3	11	Gary	Snake	77 Sewer St, City	gary_s@gmail.com	0833333333	7500.00	15000.00	6 Months	Active	2024-06-01	2024-12-01	contract_gary.pdf	sig_gary	sig_rosie	\N	\N
4	4	5	Nibbles	Mouse	99 Tiny Hole, Wall Street	nibbles@gmail.com	0844444444	5500.00	11000.00	1 Year	Active	2024-03-01	2025-03-01	contract_nibbles.pdf	sig_nibbles	sig_elle	sig_jerry	sig_tom
5	5	9	Elsa	Almond	Ice Castle, North Mountain	elsa_a@gmail.com	0855555555	6000.00	12000.00	1 Year	Active	2024-01-20	2025-01-20	contract_elsa.pdf	sig_elsa	sig_lalisa	\N	\N
6	6	2	Anna	Jones	Arendelle Palace	anna_j@gmail.com	0866666666	4500.00	9000.00	1 Year	Ended	2023-01-01	2024-01-01	contract_anna_old.pdf	sig_anna	sig_elle	\N	\N
\.


--
-- TOC entry 3989 (class 0 OID 16469)
-- Dependencies: 220
-- Data for Name: User_Account; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."User_Account" ("User_ID", "Email", "Account_Status", "Role", "Firebase_UID", "Created_At") FROM stdin;
1	Nick@gmail.com	Active	Tenant	uid_nick_wilde	2026-01-12 11:37:28.631504+07
2	Judy@gmail.com	Active	Tenant	uid_judy_hopps	2026-01-12 11:37:28.631504+07
3	Gary@gmail.com	Active	Tenant	uid_gary_snake	2026-01-12 11:37:28.631504+07
4	Nibbles@gmail.com	Active	Tenant	uid_nibbles_m	2026-01-12 11:37:28.631504+07
5	Elsa@gmail.com	Active	Tenant	uid_elsa_almond	2026-01-12 11:37:28.631504+07
6	Anna@gmail.com	Inactive	Tenant	uid_anna_jones	2026-01-12 11:37:28.631504+07
7	Kristoff@gmail.com	Inactive	Tenant	uid_kristoff_s	2026-01-12 11:37:28.631504+07
8	Olaf@gmail.com	Inactive	Tenant	uid_olaf_snow	2026-01-12 11:37:28.631504+07
9	Rapunzel@gmail.com	Inactive	Tenant	uid_rapunzel_d	2026-01-12 11:37:28.631504+07
10	Flynn@gmail.com	Inactive	Tenant	uid_flynn_rider	2026-01-12 11:37:28.631504+07
11	Elle@gmail.com	Active	Landlord	uid_elle_faning	2026-01-12 11:37:28.631504+07
12	Lalisa@gmail.com	Active	Landlord	uid_lalisa_m	2026-01-12 11:37:28.631504+07
13	Rosie@gmail.com	Active	Landlord	uid_rosie_park	2026-01-12 11:37:28.631504+07
14	Jennie@gmail.com	Active	Landlord	uid_jennie_kim	2026-01-12 11:37:28.631504+07
15	Jisoo@gmail.com	Active	Landlord	uid_jisoo_kim	2026-01-12 11:37:28.631504+07
16	Kendall@gmail.com	Inactive	Landlord	uid_kendall_j	2026-01-12 11:37:28.631504+07
17	Kylie@gmail.com	Inactive	Landlord	uid_kylie_j	2026-01-12 11:37:28.631504+07
18	Bella@gmail.com	Inactive	Landlord	uid_bella_hadid	2026-01-12 11:37:28.631504+07
19	Gigi@gmail.com	Inactive	Landlord	uid_gigi_hadid	2026-01-12 11:37:28.631504+07
20	Zayn@gmail.com	Inactive	Landlord	uid_zayn_malik	2026-01-12 11:37:28.631504+07
\.


--
-- TOC entry 4005 (class 0 OID 16626)
-- Dependencies: 236
-- Data for Name: Water_Meter; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Water_Meter" ("Meter_WaterID", "Room_ID", "RecordedDate", "currentRead", "previousRead", "collectedWaterImage") FROM stdin;
1	1	2024-12-25	1215	1200	meter_img_101.jpg
2	5	2024-12-25	235	230	meter_img_202.jpg
3	8	2024-12-25	512	500	meter_img_lalisa_201.jpg
4	9	2024-12-25	825	800	meter_img_lalisa_202.jpg
5	11	2024-12-25	118	100	meter_img_rose_101.jpg
\.


--
-- TOC entry 4032 (class 0 OID 0)
-- Dependencies: 223
-- Name: Apartment_Apartment_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Apartment_Apartment_ID_seq"', 10, true);


--
-- TOC entry 4033 (class 0 OID 0)
-- Dependencies: 231
-- Name: Bank_Account_Bank_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Bank_Account_Bank_ID_seq"', 10, true);


--
-- TOC entry 4034 (class 0 OID 0)
-- Dependencies: 243
-- Name: Bill_Payment_Bill_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Bill_Payment_Bill_ID_seq"', 5, true);


--
-- TOC entry 4035 (class 0 OID 0)
-- Dependencies: 237
-- Name: Electricity_Meter_Meter_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Electricity_Meter_Meter_ID_seq"', 5, true);


--
-- TOC entry 4036 (class 0 OID 0)
-- Dependencies: 233
-- Name: Fixed_Cost_FixedCost_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Fixed_Cost_FixedCost_ID_seq"', 15, true);


--
-- TOC entry 4037 (class 0 OID 0)
-- Dependencies: 225
-- Name: Floor_Floor_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Floor_Floor_ID_seq"', 65, true);


--
-- TOC entry 4038 (class 0 OID 0)
-- Dependencies: 221
-- Name: Landlord_Landlord_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Landlord_Landlord_ID_seq"', 10, true);


--
-- TOC entry 4039 (class 0 OID 0)
-- Dependencies: 241
-- Name: Maintenance_Request_Request_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Maintenance_Request_Request_ID_seq"', 8, true);


--
-- TOC entry 4040 (class 0 OID 0)
-- Dependencies: 239
-- Name: Notification_Notification_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Notification_Notification_ID_seq"', 6, true);


--
-- TOC entry 4041 (class 0 OID 0)
-- Dependencies: 227
-- Name: Room_Room_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Room_Room_ID_seq"', 15, true);


--
-- TOC entry 4042 (class 0 OID 0)
-- Dependencies: 229
-- Name: Tenant_Contract_Detail_Contract_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Tenant_Contract_Detail_Contract_ID_seq"', 6, true);


--
-- TOC entry 4043 (class 0 OID 0)
-- Dependencies: 219
-- Name: User_Account_User_ID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."User_Account_User_ID_seq"', 23, true);


--
-- TOC entry 4044 (class 0 OID 0)
-- Dependencies: 235
-- Name: Water_Meter_Meter_WaterID_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Water_Meter_Meter_WaterID_seq"', 5, true);


--
-- TOC entry 3783 (class 2606 OID 16516)
-- Name: Apartment Apartment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Apartment"
    ADD CONSTRAINT "Apartment_pkey" PRIMARY KEY ("Apartment_ID");


--
-- TOC entry 3794 (class 2606 OID 16604)
-- Name: Bank_Account Bank_Account_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Bank_Account"
    ADD CONSTRAINT "Bank_Account_pkey" PRIMARY KEY ("Bank_ID");


--
-- TOC entry 3819 (class 2606 OID 25548)
-- Name: Bill_Payment Bill_Payment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Bill_Payment"
    ADD CONSTRAINT "Bill_Payment_pkey" PRIMARY KEY ("Bill_ID");


--
-- TOC entry 3806 (class 2606 OID 16651)
-- Name: Electricity_Meter Electricity_Meter_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Electricity_Meter"
    ADD CONSTRAINT "Electricity_Meter_pkey" PRIMARY KEY ("Meter_ID");


--
-- TOC entry 3769 (class 2606 OID 16588)
-- Name: User_Account Firebase_UID; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."User_Account"
    ADD CONSTRAINT "Firebase_UID" UNIQUE ("Firebase_UID");


--
-- TOC entry 3798 (class 2606 OID 16618)
-- Name: Fixed_Cost Fixed_Cost_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Fixed_Cost"
    ADD CONSTRAINT "Fixed_Cost_pkey" PRIMARY KEY ("FixedCost_ID");


--
-- TOC entry 3785 (class 2606 OID 16529)
-- Name: Floor Floor_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Floor"
    ADD CONSTRAINT "Floor_pkey" PRIMARY KEY ("Floor_ID");


--
-- TOC entry 3779 (class 2606 OID 16491)
-- Name: Landlord Landlord_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Landlord"
    ADD CONSTRAINT "Landlord_pkey" PRIMARY KEY ("Landlord_ID");


--
-- TOC entry 3814 (class 2606 OID 16736)
-- Name: Maintenance_Request Maintenance_Request_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Maintenance_Request"
    ADD CONSTRAINT "Maintenance_Request_pkey" PRIMARY KEY ("Request_ID");


--
-- TOC entry 3810 (class 2606 OID 16706)
-- Name: Notification Notification_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Notification"
    ADD CONSTRAINT "Notification_pkey" PRIMARY KEY ("Notification_ID");


--
-- TOC entry 3787 (class 2606 OID 16548)
-- Name: Room Room_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Room"
    ADD CONSTRAINT "Room_pkey" PRIMARY KEY ("Room_ID");


--
-- TOC entry 3791 (class 2606 OID 16573)
-- Name: Tenant_Contract_Detail Tenant_Contract_Detail_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Tenant_Contract_Detail"
    ADD CONSTRAINT "Tenant_Contract_Detail_pkey" PRIMARY KEY ("Contract_ID");


--
-- TOC entry 3771 (class 2606 OID 16477)
-- Name: User_Account User_Account_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."User_Account"
    ADD CONSTRAINT "User_Account_pkey" PRIMARY KEY ("User_ID");


--
-- TOC entry 3781 (class 2606 OID 16493)
-- Name: Landlord User_ID; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Landlord"
    ADD CONSTRAINT "User_ID" UNIQUE ("User_ID");


--
-- TOC entry 3773 (class 2606 OID 16479)
-- Name: User_Account Username; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."User_Account"
    ADD CONSTRAINT "Username" UNIQUE ("Email");


--
-- TOC entry 3802 (class 2606 OID 16633)
-- Name: Water_Meter Water_Meter_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Water_Meter"
    ADD CONSTRAINT "Water_Meter_pkey" PRIMARY KEY ("Meter_WaterID");


--
-- TOC entry 3808 (class 2606 OID 16854)
-- Name: Electricity_Meter uq_elec_room_date; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Electricity_Meter"
    ADD CONSTRAINT uq_elec_room_date UNIQUE ("Room_ID", "readingDate");


--
-- TOC entry 3775 (class 2606 OID 25315)
-- Name: User_Account uq_firebase_uid; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."User_Account"
    ADD CONSTRAINT uq_firebase_uid UNIQUE ("Firebase_UID");


--
-- TOC entry 3800 (class 2606 OID 16856)
-- Name: Fixed_Cost uq_fixedcost_name_apartment; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Fixed_Cost"
    ADD CONSTRAINT uq_fixedcost_name_apartment UNIQUE ("Apartment_ID", "FixedcostName");


--
-- TOC entry 3796 (class 2606 OID 16806)
-- Name: Bank_Account uq_landlord_banknum; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Bank_Account"
    ADD CONSTRAINT uq_landlord_banknum UNIQUE ("Landlord_ID", "B_Number");


--
-- TOC entry 3789 (class 2606 OID 16800)
-- Name: Room uq_room_per_floor; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Room"
    ADD CONSTRAINT uq_room_per_floor UNIQUE ("Floor_ID", "R_Number");


--
-- TOC entry 3777 (class 2606 OID 25313)
-- Name: User_Account uq_username; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."User_Account"
    ADD CONSTRAINT uq_username UNIQUE ("Email");


--
-- TOC entry 3804 (class 2606 OID 16850)
-- Name: Water_Meter uq_water_room_date; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Water_Meter"
    ADD CONSTRAINT uq_water_room_date UNIQUE ("Room_ID", "RecordedDate");


--
-- TOC entry 3815 (class 1259 OID 16752)
-- Name: idx_maintenance_room; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_maintenance_room ON public."Maintenance_Request" USING btree ("Room_ID");


--
-- TOC entry 3816 (class 1259 OID 16754)
-- Name: idx_maintenance_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_maintenance_status ON public."Maintenance_Request" USING btree ("M_Status");


--
-- TOC entry 3817 (class 1259 OID 16753)
-- Name: idx_maintenance_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_maintenance_user ON public."Maintenance_Request" USING btree ("User_ID");


--
-- TOC entry 3811 (class 1259 OID 16707)
-- Name: idx_notification_receiver; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_notification_receiver ON public."Notification" USING btree ("Receiver_User_ID");


--
-- TOC entry 3812 (class 1259 OID 16708)
-- Name: idx_notification_unread; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_notification_unread ON public."Notification" USING btree ("Receiver_User_ID", "Is_Read");


--
-- TOC entry 3792 (class 1259 OID 16807)
-- Name: uq_active_room_contract; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_active_room_contract ON public."Tenant_Contract_Detail" USING btree ("Room_ID") WHERE (("C_Status")::text = 'Active'::text);


--
-- TOC entry 3840 (class 2620 OID 25317)
-- Name: Landlord trg_check_landlord_role; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_check_landlord_role BEFORE INSERT OR UPDATE ON public."Landlord" FOR EACH ROW EXECUTE FUNCTION public.check_landlord_role();


--
-- TOC entry 3831 (class 2606 OID 16709)
-- Name: Notification Receiver_User_ID; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Notification"
    ADD CONSTRAINT "Receiver_User_ID" FOREIGN KEY ("Receiver_User_ID") REFERENCES public."User_Account"("User_ID") ON DELETE CASCADE NOT VALID;


--
-- TOC entry 3832 (class 2606 OID 16714)
-- Name: Notification Sender_User_ID; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Notification"
    ADD CONSTRAINT "Sender_User_ID" FOREIGN KEY ("Sender_User_ID") REFERENCES public."User_Account"("User_ID") ON DELETE SET NULL NOT VALID;


--
-- TOC entry 3821 (class 2606 OID 16777)
-- Name: Apartment fk_apartment_landlord; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Apartment"
    ADD CONSTRAINT fk_apartment_landlord FOREIGN KEY ("Landlord_ID") REFERENCES public."Landlord"("Landlord_ID") ON DELETE CASCADE;


--
-- TOC entry 3827 (class 2606 OID 16605)
-- Name: Bank_Account fk_bank_landlord; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Bank_Account"
    ADD CONSTRAINT fk_bank_landlord FOREIGN KEY ("Landlord_ID") REFERENCES public."Landlord"("Landlord_ID") ON DELETE CASCADE;


--
-- TOC entry 3836 (class 2606 OID 25549)
-- Name: Bill_Payment fk_bill_apartment; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Bill_Payment"
    ADD CONSTRAINT fk_bill_apartment FOREIGN KEY ("Apartment_ID") REFERENCES public."Apartment"("Apartment_ID");


--
-- TOC entry 3837 (class 2606 OID 25564)
-- Name: Bill_Payment fk_bill_contract; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Bill_Payment"
    ADD CONSTRAINT fk_bill_contract FOREIGN KEY ("Contract_ID") REFERENCES public."Tenant_Contract_Detail"("Contract_ID");


--
-- TOC entry 3838 (class 2606 OID 25554)
-- Name: Bill_Payment fk_bill_room; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Bill_Payment"
    ADD CONSTRAINT fk_bill_room FOREIGN KEY ("Room_ID") REFERENCES public."Room"("Room_ID");


--
-- TOC entry 3839 (class 2606 OID 25559)
-- Name: Bill_Payment fk_bill_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Bill_Payment"
    ADD CONSTRAINT fk_bill_user FOREIGN KEY ("User_ID") REFERENCES public."User_Account"("User_ID");


--
-- TOC entry 3825 (class 2606 OID 16579)
-- Name: Tenant_Contract_Detail fk_contract_room; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Tenant_Contract_Detail"
    ADD CONSTRAINT fk_contract_room FOREIGN KEY ("Room_ID") REFERENCES public."Room"("Room_ID");


--
-- TOC entry 3826 (class 2606 OID 16574)
-- Name: Tenant_Contract_Detail fk_contract_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Tenant_Contract_Detail"
    ADD CONSTRAINT fk_contract_user FOREIGN KEY ("User_ID") REFERENCES public."User_Account"("User_ID");


--
-- TOC entry 3830 (class 2606 OID 16652)
-- Name: Electricity_Meter fk_electric_room; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Electricity_Meter"
    ADD CONSTRAINT fk_electric_room FOREIGN KEY ("Room_ID") REFERENCES public."Room"("Room_ID") ON DELETE CASCADE;


--
-- TOC entry 3828 (class 2606 OID 16619)
-- Name: Fixed_Cost fk_fixedcost_apartment; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Fixed_Cost"
    ADD CONSTRAINT fk_fixedcost_apartment FOREIGN KEY ("Apartment_ID") REFERENCES public."Apartment"("Apartment_ID") ON DELETE CASCADE;


--
-- TOC entry 3822 (class 2606 OID 16792)
-- Name: Floor fk_floor_apartment; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Floor"
    ADD CONSTRAINT fk_floor_apartment FOREIGN KEY ("Apartment_ID") REFERENCES public."Apartment"("Apartment_ID") ON DELETE CASCADE;


--
-- TOC entry 3820 (class 2606 OID 16494)
-- Name: Landlord fk_landlord_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Landlord"
    ADD CONSTRAINT fk_landlord_user FOREIGN KEY ("User_ID") REFERENCES public."User_Account"("User_ID") ON DELETE RESTRICT;


--
-- TOC entry 3833 (class 2606 OID 16747)
-- Name: Maintenance_Request fk_maintenance_apartment; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Maintenance_Request"
    ADD CONSTRAINT fk_maintenance_apartment FOREIGN KEY ("Apartment_ID") REFERENCES public."Apartment"("Apartment_ID");


--
-- TOC entry 3834 (class 2606 OID 16737)
-- Name: Maintenance_Request fk_maintenance_room; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Maintenance_Request"
    ADD CONSTRAINT fk_maintenance_room FOREIGN KEY ("Room_ID") REFERENCES public."Room"("Room_ID");


--
-- TOC entry 3835 (class 2606 OID 16742)
-- Name: Maintenance_Request fk_maintenance_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Maintenance_Request"
    ADD CONSTRAINT fk_maintenance_user FOREIGN KEY ("User_ID") REFERENCES public."User_Account"("User_ID");


--
-- TOC entry 3823 (class 2606 OID 16549)
-- Name: Room fk_room_apartment; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Room"
    ADD CONSTRAINT fk_room_apartment FOREIGN KEY ("Apartment_ID") REFERENCES public."Apartment"("Apartment_ID");


--
-- TOC entry 3824 (class 2606 OID 16554)
-- Name: Room fk_room_floor; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Room"
    ADD CONSTRAINT fk_room_floor FOREIGN KEY ("Floor_ID") REFERENCES public."Floor"("Floor_ID");


--
-- TOC entry 3829 (class 2606 OID 16634)
-- Name: Water_Meter fk_water_room; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Water_Meter"
    ADD CONSTRAINT fk_water_room FOREIGN KEY ("Room_ID") REFERENCES public."Room"("Room_ID") ON DELETE CASCADE;


-- Completed on 2026-01-16 22:04:30 +07

--
-- PostgreSQL database dump complete
--

\unrestrict DiNDcKWb1s0MYOSS6tEwyHvKtRSo44IK01AbQ7D4E2fZRHcA0f5ABjS7pWqXIa5

